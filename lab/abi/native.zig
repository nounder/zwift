//! Experimental ARM64 Swift ABI entry points, emitted by Zig's assembler.
//! These are Swift-convention functions, NOT C-callable declarations.
//! Only the concrete signatures verified by the generated Swift oracle are supported.
const builtin = @import("builtin");
comptime {
    if (builtin.cpu.arch != .aarch64 or builtin.os.tag != .macos)
        @compileError("The native Swift ABI experiment currently requires Apple ARM64");
    asm (@import("schema.zig").assembly());
}

const Quad = extern struct { a: u64, b: u64, c: u64, d: u64 };
export fn zw_abi_quad_fill(out: *Quad, seed: u64) void {
    out.* = .{ .a = seed, .b = seed +% 1, .c = seed +% 2, .d = seed +% 3 };
}
const Bytes = extern struct { ptr: [*]const u8, len: usize };
export fn zw_abi_label(kind: u64) Bytes {
    // Static ASCII literals: Swift's literal initializer requires immortal storage.
    const text: []const u8 = switch (kind) {
        0 => "Tasks, in order.",
        1 => "A little room to write.",
        2 => "A window to the web.",
        4 => "Zig",
        else => "SwiftUI.Text, constructed in pure Zig.",
    };
    return .{ .ptr = text.ptr, .len = text.len };
}
