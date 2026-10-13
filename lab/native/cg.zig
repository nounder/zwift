//! The C drawing boundary shared by Canvas and the NSView adapter.
pub const Context = *opaque {};
pub const Point = extern struct { x: f64, y: f64 };
pub const Size = extern struct { width: f64, height: f64 };
pub const Rect = extern struct { origin: Point, size: Size };
pub fn rect(x: f64, y: f64, w: f64, h: f64) Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}
pub extern fn CGContextSaveGState(Context) void;
pub extern fn CGContextRestoreGState(Context) void;
pub extern fn CGContextSetRGBFillColor(Context, f64, f64, f64, f64) void;
pub extern fn CGContextSetRGBStrokeColor(Context, f64, f64, f64, f64) void;
pub extern fn CGContextFillRect(Context, Rect) void;
pub extern fn CGContextFillEllipseInRect(Context, Rect) void;
pub extern fn CGContextTranslateCTM(Context, f64, f64) void;
pub extern fn CGContextRotateCTM(Context, f64) void;
pub extern fn CGContextClipToRect(Context, Rect) void;
pub extern fn CGContextSetLineWidth(Context, f64) void;
pub extern fn CGContextSetLineCap(Context, c_int) void;
pub extern fn CGContextSetLineJoin(Context, c_int) void;
pub extern fn CGContextBeginPath(Context) void;
pub extern fn CGContextMoveToPoint(Context, f64, f64) void;
pub extern fn CGContextAddLineToPoint(Context, f64, f64) void;
pub extern fn CGContextStrokePath(Context) void;
pub extern fn CGContextFillPath(Context) void;
pub const Path = *opaque {};
pub extern fn CGPathCreateMutable() ?Path;
pub extern fn CGPathRelease(Path) void;
pub extern fn CGPathMoveToPoint(Path, ?*const anyopaque, f64, f64) void;
pub extern fn CGPathAddLineToPoint(Path, ?*const anyopaque, f64, f64) void;
pub extern fn CGPathAddEllipseInRect(Path, ?*const anyopaque, Rect) void;
pub extern fn CGContextAddPath(Context, Path) void;
pub extern fn CGColorSpaceCreateDeviceRGB() *anyopaque;
pub extern fn CGColorSpaceRelease(*anyopaque) void;
pub extern fn CGBitmapContextCreate(?*anyopaque, usize, usize, usize, usize, *anyopaque, u32) ?Context;
pub extern fn CGContextRelease(Context) void;
