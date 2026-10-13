//! SwiftUI owns the window and representable lifecycle. Zig owns the NSView
//! subclass, its model, drawing and AppKit event methods. No Swift adapter.
const std = @import("std");
const objc = @import("objc");
const O = objc.Object;
const cg = @import("cg.zig");
const M = @import("paint_model.zig");
const probe = @import("probe.zig");
const allocator = std.heap.c_allocator;
const State = struct { model: M.Model = .{ .allocator = allocator }, draws: usize = 0, events: usize = 0 };
var view_class: objc.Class = undefined;
var last_view: ?O = null; // Weak; cleared synchronously by dealloc on the main thread.
var made: usize = 0;
var updated: usize = 0;
var dismantled: usize = 0;
var released: usize = 0;
var test_phase: u8 = 0;
const toolbar_height = 64;
const cell_width = 64;
const labels = [_][*:0]const u8{ "Black", "Red", "Blue", "Green", "Eraser", "Thinner", "Wider", "Undo", "Redo", "Clear" };
const colors = [_][3]f64{ .{ 0.08, 0.08, 0.09 }, .{ 0.9, 0.12, 0.12 }, .{ 0.1, 0.35, 0.9 }, .{ 0.1, 0.65, 0.25 }, .{ 1, 1, 1 } };

fn state(view: O) *State {
    return objc.getIvar(view, *State, "zigState").?;
}
fn method(comptime selector: [:0]const u8, implementation: anytype, comptime encoding: [:0]const u8) void {
    std.debug.assert(objc.addMethod(view_class, objc.sel(selector), @ptrCast(&implementation), encoding));
}
pub fn install() void {
    view_class = objc.allocateClassPair(objc.class("NSView"), "ZwiftPaintSurface") orelse @panic("NSView class registration failed");
    std.debug.assert(objc.addIvar(view_class, "zigState", @sizeOf(usize), 3, "^v"));
    method("drawRect:", drawRect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}");
    method("mouseDown:", mouseDown, "v@:@");
    method("mouseDragged:", mouseDragged, "v@:@");
    method("mouseUp:", mouseUp, "v@:@");
    method("keyDown:", keyDown, "v@:@");
    method("isFlipped", yes, "B@:");
    method("acceptsFirstResponder", yes, "B@:");
    method("acceptsFirstMouse:", firstMouse, "B@:@");
    method("dealloc", dealloc, "v@:");
    objc.registerClassPair(view_class);
}
export fn zw_paint_make() O {
    const view = objc.send(objc.send(view_class, "alloc", O, .{}), "initWithFrame:", O, .{cg.rect(0, 0, 800, 600)});
    const s = allocator.create(State) catch @panic("Paint state allocation failed");
    s.* = .{};
    objc.setIvar(view, "zigState", s);
    last_view = view;
    made += 1;
    probe.root();
    return view; // makeNSView requires an owned (+1) Objective-C result.
}
export fn zw_paint_update(view: O) void {
    updated += 1;
    invalidate(view);
}
export fn zw_paint_dismantle(view: O) void {
    dismantled += 1;
    state(view).model.cancel();
}
const Super = extern struct { receiver: O, superclass: objc.Class };
extern fn objc_msgSendSuper(*Super, objc.Sel) void;
fn dealloc(view: O, _: objc.Sel) callconv(.c) void {
    const s = state(view);
    s.model.deinit();
    allocator.destroy(s);
    if (last_view == view) last_view = null;
    released += 1;
    var super = Super{ .receiver = view, .superclass = objc.class("NSView") };
    objc_msgSendSuper(&super, objc.sel("dealloc"));
}
fn yes(_: O, _: objc.Sel) callconv(.c) bool {
    return true;
}
fn firstMouse(_: O, _: objc.Sel, _: O) callconv(.c) bool {
    return true;
}
fn invalidate(view: O) void {
    objc.send(view, "setNeedsDisplay:", void, .{true});
}
fn location(view: O, event: O) cg.Point {
    const p = objc.send(event, "locationInWindow", cg.Point, .{});
    return objc.send(view, "convertPoint:fromView:", cg.Point, .{ p, @as(?O, null) });
}
fn mouseDown(view: O, _: objc.Sel, event: O) callconv(.c) void {
    const s = state(view);
    s.events += 1;
    const p = location(view, event);
    if (p.y < toolbar_height) {
        if (p.x >= 0 and p.x < labels.len * cell_width) {
            switch (@as(usize, @intFromFloat(p.x / cell_width))) {
                0...4 => |index| s.model.color = @enumFromInt(index),
                5 => s.model.width = @max(1, s.model.width - 2),
                6 => s.model.width = @min(48, s.model.width + 2),
                7 => s.model.undo(),
                8 => s.model.redo(),
                9 => s.model.clear(),
                else => unreachable,
            }
        }
    } else {
        if (objc.send(view, "window", ?O, .{})) |window| _ = objc.send(window, "makeFirstResponder:", bool, .{view});
        s.model.begin(p) catch s.model.cancel();
    }
    invalidate(view);
}
fn mouseDragged(view: O, _: objc.Sel, event: O) callconv(.c) void {
    state(view).events += 1;
    state(view).model.move(location(view, event)) catch state(view).model.cancel();
    invalidate(view);
}
fn mouseUp(view: O, _: objc.Sel, event: O) callconv(.c) void {
    state(view).events += 1;
    const model = &state(view).model;
    model.move(location(view, event)) catch model.cancel();
    model.finish() catch model.cancel();
    invalidate(view);
}
fn keyDown(view: O, _: objc.Sel, event: O) callconv(.c) void {
    const ns = objc.send(event, "charactersIgnoringModifiers", ?O, .{}) orelse return;
    const chars = objc.toZigString(ns) orelse return;
    const flags = objc.send(event, "modifierFlags", u64, .{});
    const model = &state(view).model;
    if (chars[0] == 'z' and flags & (1 << 20) != 0) {
        if (flags & (1 << 17) != 0) model.redo() else model.undo();
    } else if (chars[0] == 'e') {
        model.color = .eraser;
    }
    invalidate(view);
}
fn drawStroke(context: cg.Context, stroke: *const M.Stroke) void {
    const c = colors[@intFromEnum(stroke.color)];
    cg.CGContextSetRGBStrokeColor(context, c[0], c[1], c[2], 1);
    cg.CGContextSetRGBFillColor(context, c[0], c[1], c[2], 1);
    cg.CGContextSetLineWidth(context, stroke.width);
    cg.CGContextSetLineCap(context, 1);
    cg.CGContextSetLineJoin(context, 1);
    const points = stroke.points.items;
    const first = points[0];
    if (points.len == 1) {
        cg.CGContextFillEllipseInRect(context, cg.rect(first.x - stroke.width / 2, first.y - stroke.width / 2, stroke.width, stroke.width));
    } else {
        cg.CGContextBeginPath(context);
        cg.CGContextMoveToPoint(context, first.x, first.y);
        for (points[1..]) |p| cg.CGContextAddLineToPoint(context, p.x, p.y);
        cg.CGContextStrokePath(context);
    }
}
fn drawModel(context: cg.Context, model: *const M.Model, bounds: cg.Rect) void {
    cg.CGContextSaveGState(context);
    defer cg.CGContextRestoreGState(context);
    cg.CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    cg.CGContextFillRect(context, bounds);
    cg.CGContextClipToRect(context, cg.rect(0, toolbar_height, bounds.size.width, @max(0, bounds.size.height - toolbar_height)));
    for (model.strokes.items[0..model.visible]) |*stroke| drawStroke(context, stroke);
    if (model.active) |*stroke| drawStroke(context, stroke);
}
fn drawRect(view: O, _: objc.Sel, _: cg.Rect) callconv(.c) void {
    const s = state(view);
    s.draws += 1;
    const graphics = objc.send(objc.class("NSGraphicsContext"), "currentContext", O, .{});
    const context = objc.send(graphics, "CGContext", cg.Context, .{});
    const bounds = objc.send(view, "bounds", cg.Rect, .{});
    drawModel(context, &s.model, bounds);
    cg.CGContextSetRGBFillColor(context, 0.93, 0.94, 0.96, 1);
    cg.CGContextFillRect(context, cg.rect(0, 0, bounds.size.width, toolbar_height));
    for (labels, 0..) |label, i| {
        const x: f64 = @floatFromInt(i * cell_width);
        if (i < colors.len) {
            const c = colors[i];
            cg.CGContextSetRGBFillColor(context, c[0], c[1], c[2], 1);
            cg.CGContextFillRect(context, cg.rect(x + 8, 8, 48, 16));
            if (i == @intFromEnum(s.model.color)) {
                cg.CGContextSetRGBFillColor(context, 0, 0, 0, 1);
                cg.CGContextFillRect(context, cg.rect(x + 8, 58, 48, 3));
            }
        }
        objc.send(objc.nsString(label), "drawAtPoint:withAttributes:", void, .{ cg.Point{ .x = x + 8, .y = 34 }, @as(?O, null) });
    }
    var buffer: [64]u8 = undefined;
    const status = std.fmt.bufPrintZ(&buffer, "Brush {d:.0}px", .{s.model.width}) catch unreachable;
    objc.send(objc.nsString(status), "drawAtPoint:withAttributes:", void, .{ cg.Point{ .x = 654, .y = 34 }, @as(?O, null) });
}

// Integration tests deliver NSEvents through NSWindow, then inspect Zig state
// and rendered pixels. They never substitute direct model calls for UI input.
fn sendMouse(view: O, kind: u64, x: f64, y: f64) void {
    const window = objc.send(view, "window", O, .{});
    const p = objc.send(view, "convertPoint:toView:", cg.Point, .{ cg.Point{ .x = x, .y = y }, @as(?O, null) });
    const number = objc.send(window, "windowNumber", i64, .{});
    const e = objc.send(objc.class("NSEvent"), "mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:", O, .{ kind, p, @as(u64, 0), @as(f64, 0), number, @as(?O, null), @as(i64, 0), @as(i64, 1), @as(f32, 1) });
    objc.send(window, "sendEvent:", void, .{e});
}
fn click(view: O, index: usize) void {
    const x: f64 = @floatFromInt(index * cell_width + 32);
    sendMouse(view, 1, x, 30);
    sendMouse(view, 2, x, 30);
}
fn sendUndoKey(view: O, redo: bool) void {
    const window = objc.send(view, "window", O, .{});
    const flags: u64 = (1 << 20) | (if (redo) @as(u64, 1 << 17) else 0);
    const e = objc.send(objc.class("NSEvent"), "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:", O, .{ @as(u64, 10), cg.Point{ .x = 0, .y = 0 }, flags, @as(f64, 0), objc.send(window, "windowNumber", i64, .{}), @as(?O, null), objc.nsString("z"), objc.nsString("z"), false, @as(u16, 6) });
    objc.send(window, "sendEvent:", void, .{e});
}
fn pixel(model: *const M.Model, x: usize, y: usize) [4]u8 {
    const bytes = allocator.alloc(u8, 800 * 600 * 4) catch @panic("test bitmap allocation failed");
    defer allocator.free(bytes);
    const space = cg.CGColorSpaceCreateDeviceRGB();
    defer cg.CGColorSpaceRelease(space);
    const context = cg.CGBitmapContextCreate(bytes.ptr, 800, 600, 8, 800 * 4, space, 1 | (4 << 12)) orelse @panic("test bitmap context failed");
    defer cg.CGContextRelease(context);
    drawModel(context, model, cg.rect(0, 0, 800, 600));
    return bytes[((599 - y) * 800 + x) * 4 ..][0..4].*; // RGBA; memory rows run opposite to the bitmap user-space y axis.
}
pub fn poll() bool {
    if (test_phase == 2) {
        if (dismantled == 0 or released == 0) return false;
        probe.require(last_view == null and made == released, "Paint view/model lifetime mismatch");
        std.debug.print("PAINT_ABI_OK: make={d} update={d} dismantle={d} dealloc={d}; mouse input, brush, undo/redo, clear and pixels verified\n", .{ made, updated, dismantled, released });
        return true;
    }
    const view = last_view orelse return false;
    const window = objc.send(view, "window", ?O, .{}) orelse return false;
    if (test_phase == 0) {
        const application = objc.send(objc.class("NSApplication"), "sharedApplication", O, .{});
        objc.send(application, "activateIgnoringOtherApps:", void, .{true});
        objc.send(window, "setContentSize:", void, .{cg.Size{ .width = 800, .height = 600 }});
        objc.send(window, "makeKeyAndOrderFront:", void, .{@as(?O, null)});
        test_phase = 1;
        return false;
    }
    const s = state(view);
    click(view, 1); // Red.
    sendMouse(view, 1, 100, 120);
    sendMouse(view, 6, 180, 150);
    sendMouse(view, 2, 220, 180);
    probe.require(s.model.visible == 1 and s.model.strokes.items[0].points.items.len == 3, "Paint mouse events did not reach Zig through NSWindow");
    probe.require(s.model.strokes.items[0].color == .red, "Paint palette input");
    const red = pixel(&s.model, 180, 150);
    probe.require(red[0] > 180 and red[1] < 80, "Paint stroke pixels");
    click(view, 6); // Wider, blue, then a single-click dot.
    click(view, 2);
    sendMouse(view, 1, 300, 250);
    sendMouse(view, 2, 300, 250);
    probe.require(s.model.visible == 2 and s.model.strokes.items[1].width == 8, "Paint brush width and dot");
    click(view, 7);
    probe.require(s.model.visible == 1, "Paint undo");
    click(view, 8);
    probe.require(s.model.visible == 2, "Paint redo");
    const blue = pixel(&s.model, 300, 250);
    probe.require(blue[2] > 180 and blue[0] < 80, "Paint redo pixels");
    objc.send(view, "displayIfNeeded", void, .{});
    probe.require(s.draws > 0 and s.events >= 15 and updated > 0, "Paint drawing/update callbacks");
    probe.capture(view);
    click(view, 4); // Erase the red stroke, then undo/redo through key events.
    sendMouse(view, 1, 100, 120);
    sendMouse(view, 6, 180, 150);
    sendMouse(view, 2, 220, 180);
    const erased = pixel(&s.model, 180, 150);
    probe.require(s.model.visible == 3 and erased[0] == 255 and erased[1] == 255, "Paint eraser pixels");
    sendUndoKey(view, false);
    const restored = pixel(&s.model, 180, 150);
    probe.require(s.model.visible == 2 and restored[0] > 180 and restored[1] < 80, "Paint keyboard undo restores erased stroke");
    sendUndoKey(view, true);
    probe.require(s.model.visible == 3, "Paint keyboard redo");
    click(view, 9);
    const white = pixel(&s.model, 180, 150);
    probe.require(s.model.visible == 0 and white[0] == 255 and white[1] == 255 and white[2] == 255, "Paint clear pixels");
    // Detach the real SwiftUI hosting tree, exercising dismantle and release.
    _ = objc.send(window, "retain", O, .{});
    defer objc.send(window, "release", void, .{});
    objc.send(window, "close", void, .{});
    objc.send(window, "setContentView:", void, .{@as(?O, null)});
    test_phase = 2;
    return false;
}
