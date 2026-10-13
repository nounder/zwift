//! Deterministic animation state; the SwiftUI timeline supplies frame cadence.
const std = @import("std");
pub const Frame = struct { travel: f64, scale: f64, opacity: f64, rotation: f64 };
pub fn sample(seconds: f64) Frame {
    const phase = @mod(seconds, 4.0) * (std.math.pi / 2.0);
    const wave = (1 - @cos(phase)) * 0.5;
    return .{ .travel = wave, .scale = 0.6 + wave * 0.6, .opacity = 0.2 + wave * 0.8, .rotation = phase };
}
test "animation has deterministic endpoints, midpoint and periodicity" {
    const t = std.testing;
    try t.expectEqual(@as(f64, 0), sample(0).travel);
    try t.expectEqual(@as(f64, 1), sample(2).travel);
    try t.expectApproxEqAbs(@as(f64, 0.5), sample(1).travel, 0.00001);
    try t.expectEqualDeep(sample(0.75), sample(4.75));
    try t.expectEqualDeep(sample(3), sample(-1));
}
test "animation values remain bounded across many cycles" {
    for (0..10000) |i| {
        const f = sample(@as(f64, @floatFromInt(i)) / 60);
        try std.testing.expect(f.travel >= 0 and f.travel <= 1 and f.scale >= 0.6 and f.scale <= 1.2 and f.opacity >= 0.2 and f.opacity <= 1);
    }
}
