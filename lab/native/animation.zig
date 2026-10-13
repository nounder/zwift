//! TimelineView<AnimationTimelineSchedule, Canvas<EmptyView>>, entirely emitted
//! from Zig. Swift owns scheduling, Canvas and escaping closure reference counts.
const std = @import("std");
const R = @import("runtime.zig");
const ABI = @import("animation_abi.zig");
const cg = @import("cg.zig");
const probe = @import("probe.zig");
const objc = @import("objc");
extern fn zw_schedule_init(*anyopaque) void;
extern fn zw_timeline_init(*anyopaque, *anyopaque, R.Metadata, R.Metadata, R.Metadata, R.Metadata) void;
extern fn zw_canvas_init(*anyopaque, *anyopaque, *anyopaque) void;
extern fn swift_allocObject(R.Metadata, usize, usize) *anyopaque;
extern fn swift_deallocObject(*anyopaque, usize, usize) void;
extern fn CACurrentMediaTime() f64;
extern const zw_capture_metadata: anyopaque;
extern const @"$s7SwiftUI16TimelineScheduleMp": anyopaque;
extern const @"$s7SwiftUI18ColorRenderingModeO9nonLinearyA2CmFWC": u32;
const Capture = extern struct { header: [2]usize, time: f64 };
const Counter = std.atomic.Value(usize);
var allocated = Counter.init(0);
var destroyed = Counter.init(0);
var frames = Counter.init(0);
var changed_frames = Counter.init(0);
var previous_time = std.atomic.Value(u64).init(0);
var canvas_metadata: R.Metadata = undefined;
var schedule_metadata: R.Metadata = undefined;
var color_metadata: R.Metadata = undefined;
var timeline_metadata: R.Metadata = undefined;
var start_time: f64 = 0;
var checked = false;

pub fn install() void {
    canvas_metadata = R.metadata(ABI.canvas_type);
    schedule_metadata = R.metadata("7SwiftUI25AnimationTimelineScheduleV");
    color_metadata = R.metadata("7SwiftUI18ColorRenderingModeO");
    timeline_metadata = R.metadata(ABI.body_type);
    start_time = CACurrentMediaTime();
}
export fn zw_animation_witness() R.Metadata {
    return R.witness(timeline_metadata, &R.@"$s7SwiftUI4ViewMp");
}
export fn zw_animation_body(output: *anyopaque) void {
    probe.root();
    const schedule = R.Value.alloc(schedule_metadata);
    defer schedule.freeStorage(); // Consumed by TimelineView.init.
    zw_schedule_init(schedule.ptr);
    zw_timeline_init(output, schedule.ptr, schedule_metadata, canvas_metadata, R.witness(schedule_metadata, &@"$s7SwiftUI16TimelineScheduleMp"), R.witness(canvas_metadata, &R.@"$s7SwiftUI4ViewMp"));
}
export fn zw_make_canvas(output: *anyopaque) void {
    const color = R.Value.alloc(color_metadata);
    defer color.freeStorage(); // Consumed by Canvas.init.
    R.witnesses(color_metadata).enum_inject(color.ptr, @"$s7SwiftUI18ColorRenderingModeO9nonLinearyA2CmFWC", color_metadata);
    const capture: *Capture = @ptrCast(@alignCast(swift_allocObject(&zw_capture_metadata, @sizeOf(Capture), @alignOf(Capture) - 1)));
    capture.time = CACurrentMediaTime() - start_time;
    _ = allocated.fetchAdd(1, .monotonic);
    // Ownership transfers into Canvas. Every copy must retain this capture.
    zw_canvas_init(output, color.ptr, capture);
}
export fn zw_capture_destroy_c(capture: *anyopaque) void {
    _ = destroyed.fetchAdd(1, .monotonic);
    swift_deallocObject(capture, @sizeOf(Capture), @alignOf(Capture) - 1);
}
export fn zw_animation_draw(context: cg.Context, width: f64, height: f64, time: f64) void {
    const previous = previous_time.swap(@bitCast(time), .monotonic);
    if (previous != @as(u64, @bitCast(time))) _ = changed_frames.fetchAdd(1, .monotonic);
    _ = frames.fetchAdd(1, .monotonic);
    const f = @import("motion.zig").sample(time);
    cg.CGContextSetRGBFillColor(context, 0.07, 0.09, 0.15, 1);
    cg.CGContextFillRect(context, cg.rect(0, 0, width, height));
    const radius = @min(width, height) * 0.08;
    cg.CGContextSetRGBFillColor(context, 0.2, 0.65, 1, 1);
    cg.CGContextFillEllipseInRect(context, cg.rect(radius + f.travel * @max(0, width - 4 * radius), height * 0.2, radius * 2, radius * 2));
    cg.CGContextSaveGState(context);
    cg.CGContextTranslateCTM(context, width * 0.5, height * 0.58);
    cg.CGContextRotateCTM(context, f.rotation);
    cg.CGContextSetRGBFillColor(context, 1, 0.4, 0.3, f.opacity);
    const side = radius * 2 * f.scale;
    cg.CGContextFillRect(context, cg.rect(-side / 2, -side / 2, side, side));
    cg.CGContextRestoreGState(context);
}
pub fn poll() bool {
    if (!checked) {
        // Test actual Swift value-witness retain/release behavior, independently
        // of the live SwiftUI graph. Destruction must happen exactly once.
        const before = destroyed.load(.monotonic);
        const value = R.Value.alloc(canvas_metadata);
        zw_make_canvas(value.ptr);
        const copy = value.clone();
        value.deinit();
        probe.require(destroyed.load(.monotonic) == before, "Canvas copy did not retain renderer context");
        copy.deinit();
        probe.require(destroyed.load(.monotonic) == before + 1, "Canvas context not destroyed exactly once");
        checked = true;
        const application = objc.send(objc.class("NSApplication"), "sharedApplication", objc.Object, .{});
        const window = objc.send(application, "mainWindow", ?objc.Object, .{});
        if (window) |w| objc.send(w, "setContentSize:", void, .{cg.Size{ .width = 800, .height = 600 }});
    }
    if (frames.load(.monotonic) < 4 or changed_frames.load(.monotonic) < 3) return false;
    probe.require(destroyed.load(.monotonic) > 1, "SwiftUI did not release superseded renderer captures");
    const application = objc.send(objc.class("NSApplication"), "sharedApplication", objc.Object, .{});
    const windows = objc.send(application, "windows", objc.Object, .{});
    const window = objc.send(windows, "objectAtIndex:", objc.Object, .{@as(usize, 0)});
    probe.capture(objc.send(window, "contentView", objc.Object, .{}));
    std.debug.print("ANIMATION_ABI_OK: rendered={d} changed={d} captures={d} released={d}; Canvas copy/destroy ownership verified\n", .{
        frames.load(.monotonic), changed_frames.load(.monotonic), allocated.load(.monotonic), destroyed.load(.monotonic),
    });
    return true;
}
