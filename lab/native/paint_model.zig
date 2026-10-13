//! One Zig-owned model per NSView instance. Completed strokes are immutable;
//! undo/redo moves a cursor without copying their point buffers.
const std = @import("std");
pub const Point = @import("cg.zig").Point;
pub const Color = enum { black, red, blue, green, eraser };
pub const Stroke = struct { points: std.ArrayList(Point) = .empty, color: Color, width: f64 };
pub const Model = struct {
    allocator: std.mem.Allocator,
    strokes: std.ArrayList(Stroke) = .empty,
    visible: usize = 0,
    active: ?Stroke = null,
    color: Color = .black,
    width: f64 = 6,

    pub fn deinit(self: *Model) void {
        self.clear();
        self.strokes.deinit(self.allocator);
    }
    pub fn begin(self: *Model, point: Point) !void {
        if (!valid(point)) return;
        var stroke: Stroke = .{ .color = self.color, .width = self.width };
        try stroke.points.append(self.allocator, point);
        self.cancel();
        self.active = stroke;
    }
    pub fn move(self: *Model, point: Point) !void {
        if (!valid(point)) return;
        if (self.active) |*stroke| {
            const last = stroke.points.getLast();
            if (last.x == point.x and last.y == point.y) return;
            try stroke.points.append(self.allocator, point);
        }
    }
    pub fn finish(self: *Model) !void {
        const stroke = self.active orelse return;
        // Reserve before dropping redo history, so allocation failure keeps both
        // the active stroke and all previous history intact.
        try self.strokes.ensureTotalCapacity(self.allocator, self.visible + 1);
        for (self.strokes.items[self.visible..]) |*redo_stroke| redo_stroke.points.deinit(self.allocator);
        self.strokes.shrinkRetainingCapacity(self.visible);
        self.strokes.appendAssumeCapacity(stroke);
        self.visible += 1;
        self.active = null;
    }
    pub fn cancel(self: *Model) void {
        if (self.active) |*stroke| stroke.points.deinit(self.allocator);
        self.active = null;
    }
    pub fn undo(self: *Model) void {
        self.cancel();
        self.visible -|= 1;
    }
    pub fn redo(self: *Model) void {
        self.cancel();
        self.visible = @min(self.strokes.items.len, self.visible + 1);
    }
    pub fn clear(self: *Model) void {
        self.cancel();
        for (self.strokes.items) |*stroke| stroke.points.deinit(self.allocator);
        self.strokes.clearRetainingCapacity();
        self.visible = 0;
    }
};
fn valid(point: Point) bool {
    return std.math.isFinite(point.x) and std.math.isFinite(point.y);
}
test "stroke captures brush settings and click paints a dot" {
    var m: Model = .{ .allocator = std.testing.allocator };
    defer m.deinit();
    try m.begin(.{ .x = 10, .y = 20 });
    m.color = .red;
    m.width = 20;
    try m.move(.{ .x = 10, .y = 20 });
    try m.finish();
    try std.testing.expectEqual(@as(usize, 1), m.visible);
    try std.testing.expectEqual(@as(usize, 1), m.strokes.items[0].points.items.len);
    try std.testing.expectEqual(Color.black, m.strokes.items[0].color);
    try std.testing.expectEqual(@as(f64, 6), m.strokes.items[0].width);
}
test "undo redo branches, clear and independent models" {
    var m: Model = .{ .allocator = std.testing.allocator };
    defer m.deinit();
    var other: Model = .{ .allocator = std.testing.allocator };
    defer other.deinit();
    m.undo();
    m.redo();
    for (0..3) |i| {
        try m.begin(.{ .x = @floatFromInt(i), .y = 10 });
        try m.move(.{ .x = 100, .y = 20 });
        try m.finish();
    }
    m.undo();
    m.undo();
    m.redo();
    try std.testing.expectEqual(@as(usize, 2), m.visible);
    m.color = .eraser;
    try m.begin(.{ .x = 5, .y = 6 });
    try m.finish();
    m.redo();
    try std.testing.expectEqual(@as(usize, 3), m.strokes.items.len);
    try std.testing.expectEqual(Color.eraser, m.strokes.items[2].color);
    try std.testing.expectEqual(@as(usize, 0), other.visible);
    try m.begin(.{ .x = 8, .y = 9 });
    m.clear();
    try std.testing.expect(m.active == null and m.visible == 0 and m.strokes.items.len == 0);
}
test "invalid input never reaches CoreGraphics and cancelled strokes don't enter history" {
    var m: Model = .{ .allocator = std.testing.allocator };
    defer m.deinit();
    try m.begin(.{ .x = std.math.nan(f64), .y = 0 });
    try std.testing.expect(m.active == null);
    try m.begin(.{ .x = 1, .y = 2 });
    try m.move(.{ .x = std.math.inf(f64), .y = 0 });
    try std.testing.expectEqual(@as(usize, 1), m.active.?.points.items.len);
    m.undo();
    try std.testing.expect(m.active == null and m.visible == 0);
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var m: Model = .{ .allocator = allocator };
    defer m.deinit();
    try m.begin(.{ .x = 1, .y = 2 });
    for (0..30) |i| try m.move(.{ .x = @floatFromInt(i), .y = 4 });
    try m.finish();
    m.undo();
    try m.begin(.{ .x = 5, .y = 6 });
    try m.finish();
}
test "all stroke allocation failures clean up without leaking" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
