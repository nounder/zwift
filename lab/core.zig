//! Main-thread-only owned stores. No Swift object layouts cross this C boundary.
const std = @import("std");
const a = if (@import("builtin").is_test) std.testing.allocator else std.heap.c_allocator;
pub const Change = ?*const fn (?*anyopaque, u64) callconv(.c) void;
pub const Environment = extern struct { dark: u32 = 0, compact: u32 = 0, allow_http: u32 = 0 };
pub const Stats = extern struct { bytes: u64 = 0, scalars: u64 = 0, words: u64 = 0, lines: u64 = 1 };
pub const TodoInfo = extern struct { id: u64 = 0, title_bytes: usize = 0, done: u32 = 0 };
const Todo = struct { id: u64, title: []u8, done: bool = false };
const Store = struct {
    todos: std.ArrayList(Todo) = .empty,
    next_id: u64 = 1,
    text: []u8 = &.{},
    url: []u8 = &.{},
    revision: u64 = 0,
    env: Environment = .{},
    callback: Change = null,
    context: ?*anyopaque = null,
    fn changed(s: *Store, mask: u64) void {
        s.revision +%= 1;
        if (s.callback) |f| f(s.context, mask);
    }
};
fn store(p: *anyopaque) *Store {
    return @ptrCast(@alignCast(p));
}
fn copy(bytes: []const u8, out: ?[*]u8, cap: usize) usize {
    if (out) |p| @memcpy(p[0..@min(cap, bytes.len)], bytes[0..@min(cap, bytes.len)]);
    return bytes.len;
}
fn replace(dst: *[]u8, bytes: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(bytes)) return false;
    const owned = a.dupe(u8, bytes) catch return false;
    a.free(dst.*);
    dst.* = owned;
    return true;
}
pub export fn zw_create() ?*anyopaque {
    const s = a.create(Store) catch return null;
    s.* = .{};
    return s;
}
pub export fn zw_destroy(p: *anyopaque) void {
    const s = store(p);
    for (s.todos.items) |t| a.free(t.title);
    s.todos.deinit(a);
    a.free(s.text);
    a.free(s.url);
    a.destroy(s);
}
pub export fn zw_observe(p: *anyopaque, callback: Change, context: ?*anyopaque) void {
    const s = store(p);
    s.callback = callback;
    s.context = context;
}
pub export fn zw_revision(p: *anyopaque) u64 {
    return store(p).revision;
}
pub export fn zw_environment(p: *anyopaque, env: Environment) void {
    const s = store(p);
    if (std.meta.eql(s.env, env)) return;
    s.env = env;
    s.changed(8);
}
pub export fn zw_environment_get(p: *anyopaque) Environment {
    return store(p).env;
}
pub export fn zw_todo_count(p: *anyopaque) usize {
    return store(p).todos.items.len;
}
pub export fn zw_todo_id(p: *anyopaque, index: usize) u64 {
    const ts = store(p).todos.items;
    return if (index < ts.len) ts[index].id else 0;
}
// Index-based snapshot read avoids searching the same array for every field.
// No mutation may occur between the size query and copy (main-thread contract).
pub export fn zw_todo_at(p: *anyopaque, index: usize, out: ?[*]u8, cap: usize) TodoInfo {
    const todos = store(p).todos.items;
    if (index >= todos.len) return .{};
    const t = todos[index];
    return .{ .id = t.id, .title_bytes = copy(t.title, out, cap), .done = @intFromBool(t.done) };
}
pub export fn zw_todo_title(p: *anyopaque, id: u64, out: ?[*]u8, cap: usize) usize {
    for (store(p).todos.items) |t| {
        if (t.id == id) return copy(t.title, out, cap);
    }
    return 0;
}
pub export fn zw_todo_done(p: *anyopaque, id: u64) u32 {
    for (store(p).todos.items) |t| {
        if (t.id == id) return @intFromBool(t.done);
    }
    return 0;
}
pub export fn zw_todo_add(p: *anyopaque, ptr: [*]const u8, len: usize) u64 {
    const s = store(p);
    const title = std.mem.trim(u8, ptr[0..len], " \t\r\n");
    if (title.len == 0 or title.len > 4096 or !std.unicode.utf8ValidateSlice(title) or s.next_id == 0) return 0;
    const owned = a.dupe(u8, title) catch return 0;
    const id = s.next_id;
    s.todos.append(a, .{ .id = id, .title = owned }) catch {
        a.free(owned);
        return 0;
    };
    s.next_id +%= 1;
    s.changed(1);
    return id;
}
pub export fn zw_todo_toggle(p: *anyopaque, id: u64) u32 {
    const s = store(p);
    for (s.todos.items) |*t| {
        if (t.id == id) {
            t.done = !t.done;
            s.changed(1);
            return 1;
        }
    }
    return 0;
}
pub export fn zw_todo_remove(p: *anyopaque, id: u64) u32 {
    const s = store(p);
    for (s.todos.items, 0..) |t, i| {
        if (t.id == id) {
            a.free(t.title);
            _ = s.todos.orderedRemove(i);
            s.changed(1);
            return 1;
        }
    }
    return 0;
}
// Move by identity, before another identity; before=0 means append. Safe with filtered views.
pub export fn zw_todo_move(p: *anyopaque, id: u64, before: u64) u32 {
    const s = store(p);
    if (id == before) return 0;
    var source: ?usize = null;
    var target: ?usize = if (before == 0) s.todos.items.len else null;
    for (s.todos.items, 0..) |t, i| {
        if (t.id == id) source = i;
        if (t.id == before) target = i;
    }
    const from = source orelse return 0;
    var to = target orelse return 0;
    if (from < to) to -= 1;
    if (from == to) return 0;
    const t = s.todos.orderedRemove(from);
    s.todos.insertAssumeCapacity(to, t);
    s.changed(1);
    return 1;
}
pub export fn zw_editor_set(p: *anyopaque, ptr: [*]const u8, len: usize) u32 {
    const s = store(p);
    if (std.mem.eql(u8, s.text, ptr[0..len])) return 1;
    if (!replace(&s.text, ptr[0..len])) return 0;
    s.changed(2);
    return 1;
}
pub export fn zw_editor_text(p: *anyopaque, out: ?[*]u8, cap: usize) usize {
    return copy(store(p).text, out, cap);
}
pub export fn zw_editor_stats(p: *anyopaque) Stats {
    const bytes = store(p).text;
    var stats: Stats = .{ .bytes = bytes.len };
    var in_word = false;
    // Scalars != user-perceived graphemes; word boundaries here are ASCII whitespace.
    for (bytes) |c| {
        if (c & 0xc0 != 0x80) stats.scalars += 1;
        if (c == '\n') stats.lines += 1;
        const space = std.ascii.isWhitespace(c);
        if (!space and !in_word) stats.words += 1;
        in_word = !space;
    }
    return stats;
}
pub export fn zw_browser_navigate(p: *anyopaque, ptr: [*]const u8, len: usize) u32 {
    const s = store(p);
    const input = std.mem.trim(u8, ptr[0..len], " \t\r\n");
    if (input.len == 0 or input.len > 8192 or !std.unicode.utf8ValidateSlice(input)) return 0;
    for (input) |c| {
        if (c <= 32 or c == 127) return 0;
    }
    const https = std.ascii.startsWithIgnoreCase(input, "https://");
    const http = std.ascii.startsWithIgnoreCase(input, "http://");
    if (http and s.env.allow_http == 0) return 0;
    const blank = std.mem.eql(u8, input, "about:blank");
    if (!https and !http and !blank and std.mem.indexOf(u8, input, ":") != null) return 0;
    const prefix: []const u8 = if (https or http or blank) "" else "https://";
    if ((https and input.len <= 8) or (http and input.len <= 7)) return 0;
    const url = std.mem.concat(a, u8, &.{ prefix, input }) catch return 0;
    a.free(s.url);
    s.url = url;
    s.changed(4);
    return 1;
}
pub export fn zw_browser_url(p: *anyopaque, out: ?[*]u8, cap: usize) usize {
    return copy(store(p).url, out, cap);
}

test "identity reordering, validation and independent store lifetimes" {
    const s = zw_create().?;
    defer zw_destroy(s);
    const other = zw_create().?;
    defer zw_destroy(other);
    const one = zw_todo_add(s, "one", 3);
    const two = zw_todo_add(s, "two", 3);
    const three = zw_todo_add(s, "three", 5);
    try std.testing.expectEqual(@as(u32, 1), zw_todo_move(s, one, 0));
    try std.testing.expectEqual(two, zw_todo_id(s, 0));
    try std.testing.expectEqual(one, zw_todo_id(s, 2));
    try std.testing.expectEqual(@as(u32, 1), zw_todo_move(s, three, two));
    try std.testing.expectEqual(three, zw_todo_id(s, 0));
    try std.testing.expectEqual(@as(u32, 0), zw_todo_move(s, 999, one));
    try std.testing.expectEqual(@as(u64, 0), zw_todo_add(s, "\xff", 1));
    try std.testing.expectEqual(@as(usize, 0), zw_todo_count(other));
    _ = zw_todo_toggle(s, one);
    try std.testing.expectEqual(@as(u32, 1), zw_todo_done(s, one));
    _ = zw_todo_remove(s, two);
    try std.testing.expectEqual(@as(usize, 2), zw_todo_count(s));
}
test "UTF-8 byte counts, scalar counts, rejected mutation, bounded copying" {
    const s = zw_create().?;
    defer zw_destroy(s);
    const t = "Hi 👋\nZig";
    try std.testing.expectEqual(@as(u32, 1), zw_editor_set(s, t.ptr, t.len));
    try std.testing.expectEqual(Stats{ .bytes = 11, .scalars = 8, .words = 3, .lines = 2 }, zw_editor_stats(s));
    try std.testing.expectEqual(@as(u32, 0), zw_editor_set(s, "\xff", 1));
    var out: [2]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 11), zw_editor_text(s, &out, out.len));
    try std.testing.expectEqualStrings("Hi", &out);
}
test "environment feeds URL policy and callbacks report committed changes" {
    const s = zw_create().?;
    defer zw_destroy(s);
    const Observer = struct {
        fn changed(ctx: ?*anyopaque, mask: u64) callconv(.c) void {
            const bits: *u64 = @ptrCast(@alignCast(ctx.?));
            bits.* |= mask;
        }
    };
    var bits: u64 = 0;
    zw_observe(s, Observer.changed, &bits);
    try std.testing.expectEqual(@as(u32, 0), zw_browser_navigate(s, "http://example.com", 18));
    zw_environment(s, .{ .allow_http = 1, .dark = 1 });
    try std.testing.expectEqual(@as(u32, 1), zw_browser_navigate(s, "http://example.com", 18));
    try std.testing.expectEqual(@as(u64, 12), bits);
    try std.testing.expectEqual(@as(u32, 0), zw_browser_navigate(s, "javascript:alert(1)", 19));
    zw_observe(s, null, null);
    _ = zw_editor_set(s, "ok", 2);
    try std.testing.expectEqual(@as(u64, 12), bits);
}

// External optimization barrier for the benchmark; the pointee never escapes.
pub export fn zw_bench_consume(pointer: *const anyopaque) void {
    asm volatile (""
        :
        : [value] "r" (pointer),
        : .{ .memory = true });
}

test "index snapshots preserve identity after moves and bound title writes" {
    const s = zw_create().?;
    defer zw_destroy(s);
    const one = zw_todo_add(s, "hello", 5);
    const two = zw_todo_add(s, "two", 3);
    _ = zw_todo_toggle(s, one);
    _ = zw_todo_move(s, two, one);
    var buffer = [_]u8{0xcc} ** 4;
    const result = zw_todo_at(s, 1, &buffer, 2);
    try std.testing.expectEqual(one, result.id);
    try std.testing.expectEqual(@as(u32, 1), result.done);
    try std.testing.expectEqual(@as(usize, 5), result.title_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 'h', 'e', 0xcc, 0xcc }, &buffer);
    try std.testing.expectEqual(TodoInfo{}, zw_todo_at(s, 2, &buffer, 4));
}
