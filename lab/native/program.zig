//! Compile-time programs consumed by the native Swift ABI emitter.
const E = @import("emitter.zig");
pub fn named(comptime name: []const u8) E.App {
    return .{ .module = "Zwift" ++ name, .root = "ZigRoot", .app = "ZigApp", .text = "SwiftUI View and App emitted by Zig", .body = if (@import("std").mem.eql(u8, name, "Animations")) .animation else if (@import("std").mem.eql(u8, name, "Paint")) .paint else .text };
}
pub const app = named(@import("options").example);
