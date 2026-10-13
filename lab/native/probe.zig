//! Runtime verification through C/Objective-C only. Enabled by an environment
//! variable; it observes SwiftUI's window and never creates a window or host.
const std = @import("std");
const objc = @import("objc");
const Object = objc.Object;
const MetadataResponse = extern struct { metadata: *const anyopaque, state: usize };
const Name = extern struct { ptr: [*]const u8, len: usize };
extern fn getenv([*:0]const u8) ?[*:0]const u8;
extern fn exit(c_int) noreturn;
extern fn pthread_main_np() c_int;
extern fn swift_getTypeName(*const anyopaque, bool) Name;
extern fn swift_getTypeByMangledNameInContext2([*]const u8, usize, ?*const anyopaque, ?*const anyopaque) ?*const anyopaque;
extern fn swift_conformsToProtocol(*const anyopaque, *const anyopaque) ?*const anyopaque;
extern const zw_native_root_type: anyopaque;
extern const zw_native_app_type: anyopaque;
extern const @"$sytWV": anyopaque;
extern const @"$s7SwiftUI4ViewMp": anyopaque;
extern const @"$s7SwiftUI3AppMp": anyopaque;
extern const @"$s7SwiftUI5SceneMp": anyopaque;
extern fn zw_native_root_witness() *const anyopaque;
extern fn zw_native_app_witness() *const anyopaque;
extern fn zw_native_group_witness() *const anyopaque;
extern fn zw_native_group_metadata() MetadataResponse;
extern var _dispatch_main_q: anyopaque;
extern fn dispatch_time(u64, i64) u64;
extern fn dispatch_after_f(u64, *anyopaque, ?*anyopaque, *const fn (?*anyopaque) callconv(.c) void) void;

var enabled = false;
var root_calls: usize = 0;
var app_calls: usize = 0;
var attempts: usize = 0;
var verified_window = false;
var visible_windows_seen: usize = 0;

pub fn require(ok: bool, message: []const u8) void {
    if (!ok) {
        std.debug.print("NATIVE_ABI_FAIL: {s}\n", .{message});
        exit(1);
    }
}
pub fn root() void {
    if (!enabled) return;
    require(pthread_main_np() == 1, "root callback did not run on the main thread");
    root_calls += 1;
}
pub fn app() void {
    if (!enabled) return;
    require(pthread_main_np() == 1, "App.body did not run on the main thread");
    app_calls += 1;
}
fn typeName(metadata: *const anyopaque) []const u8 {
    const name = swift_getTypeName(metadata, true);
    return name.ptr[0..name.len];
}
fn metadataChecks() void {
    const spec = @import("program.zig").app;
    for ([_]*const anyopaque{ &zw_native_root_type, &zw_native_app_type }) |metadata| {
        const preceding: *const *const anyopaque = @ptrFromInt(@intFromPtr(metadata) - @sizeOf(usize));
        require(preceding.* == &@"$sytWV", "metadata value-witness prefix was not preserved by the linker");
    }
    require(std.mem.eql(u8, typeName(&zw_native_root_type), spec.module ++ "." ++ spec.root), "root type name");
    require(std.mem.eql(u8, typeName(&zw_native_app_type), spec.module ++ "." ++ spec.app), "app type name");
    const mangled = std.fmt.comptimePrint("{d}{s}{d}{s}V", .{ spec.module.len, spec.module, spec.root.len, spec.root });
    require(swift_getTypeByMangledNameInContext2(mangled.ptr, mangled.len, null, null) == &zw_native_root_type, "runtime nominal type lookup");
    require(swift_conformsToProtocol(&zw_native_root_type, &@"$s7SwiftUI4ViewMp") == zw_native_root_witness(), "runtime View conformance lookup");
    require(swift_conformsToProtocol(&zw_native_app_type, &@"$s7SwiftUI3AppMp") == zw_native_app_witness(), "runtime App conformance lookup");
    require(swift_conformsToProtocol(&zw_native_root_type, &@"$s7SwiftUI3AppMp") == null, "View must not accidentally conform to App");
    require(swift_conformsToProtocol(&zw_native_app_type, &@"$s7SwiftUI4ViewMp") == null, "App must not accidentally conform to View");
    const group = zw_native_group_metadata();
    require(group.state == 0, "WindowGroup metadata not complete");
    require(std.mem.indexOf(u8, typeName(group.metadata), "WindowGroup<" ++ spec.module ++ "." ++ spec.root ++ ">") != null, "generic type metadata name");
    require(swift_conformsToProtocol(group.metadata, &@"$s7SwiftUI5SceneMp") == zw_native_group_witness(), "WindowGroup Scene conformance");
    std.debug.print("NATIVE_ABI_METADATA_OK: {s}; {s}; {s}\n", .{ typeName(&zw_native_root_type), typeName(&zw_native_app_type), typeName(group.metadata) });
}
pub fn install() void {
    const mode = getenv("ZWIFT_NATIVE_PROBE") orelse return;
    enabled = true;
    // A separate launch skips preflight so SwiftUI is also tested with cold
    // generic metadata/witness caches, as in an ordinary application launch.
    if (!std.mem.eql(u8, std.mem.span(mode), "launch")) metadataChecks();
    schedule();
}
fn schedule() void {
    dispatch_after_f(dispatch_time(0, 250_000_000), &_dispatch_main_q, null, checkWindow);
}
fn checkWindow(_: ?*anyopaque) callconv(.c) void {
    attempts += 1;
    const application = objc.send(objc.getClass("NSApplication").?, "sharedApplication", Object, .{});
    const windows = objc.send(application, "windows", Object, .{});
    const count = objc.send(windows, "count", usize, .{});
    var visible: usize = 0;
    for (0..count) |i| {
        const window = objc.send(windows, "objectAtIndex:", Object, .{i});
        if (!objc.send(window, "isVisible", bool, .{})) continue;
        const content = objc.send(window, "contentView", ?Object, .{}) orelse continue;
        const size = objc.send(content, "frame", Rect, .{}).size;
        if (size.width > 0 and size.height > 0) visible += 1;
    }
    visible_windows_seen = @max(visible_windows_seen, visible);
    if (visible > 0 and root_calls > 0 and app_calls > 0) verified_window = true;
    if (!verified_window) {
        require(attempts < 40, "SwiftUI did not evaluate both bodies and show a window");
        schedule();
        return;
    }
    const ready = switch (@import("program.zig").app.body) {
        .animation => @import("animation.zig").poll(),
        .paint => @import("paint.zig").poll(),
        .text => true,
    };
    if (!ready) {
        require(attempts < 40, "native example runtime checks timed out");
        schedule();
        return;
    }
    std.debug.print("NATIVE_ABI_OK: App.body={d} root_callbacks={d} visible_windows_seen={d}\n", .{ app_calls, root_calls, visible_windows_seen });
    objc.send(application, "terminate:", void, .{@as(?Object, null)});
}
/// Optional diagnostic artifact captured from the real hosted view.
pub fn capture(view: Object) void {
    const path = getenv("ZWIFT_NATIVE_CAPTURE") orelse return;
    const bounds = objc.send(view, "bounds", Rect, .{});
    const bitmap = objc.send(view, "bitmapImageRepForCachingDisplayInRect:", ?Object, .{bounds}) orelse @panic("view bitmap allocation failed");
    objc.send(view, "cacheDisplayInRect:toBitmapImageRep:", void, .{ bounds, bitmap });
    const properties = objc.send(objc.class("NSDictionary"), "dictionary", Object, .{});
    const png = objc.send(bitmap, "representationUsingType:properties:", ?Object, .{ @as(usize, 4), properties }) orelse @panic("view PNG encoding failed");
    require(objc.send(png, "writeToFile:atomically:", bool, .{ objc.nsString(path), true }), "capture write failed");
}
const Point = extern struct { x: f64, y: f64 };
const Size = extern struct { width: f64, height: f64 };
const Rect = extern struct { origin: Point, size: Size };
