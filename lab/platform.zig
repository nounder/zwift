//! Interop lab policy: current macOS major and its immediate predecessor.
//! Current generation: macOS 27; pin the minimum explicitly for reproducible builds.
const std = @import("std");
pub const minimum_macos: std.SemanticVersion = .{ .major = 26, .minor = 0, .patch = 0 };
pub const minimum_string = std.fmt.comptimePrint("{d}.{d}", .{ minimum_macos.major, minimum_macos.minor });
pub const swift_target = "arm64-apple-macos" ++ minimum_string;
