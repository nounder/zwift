//! Explicit, audited specializations. Adding a type requires a lowering and an oracle.
const std = @import("std");
const platform = @import("../platform.zig");
pub const Kind = enum { quad, literal_text, state_u64, state_bool, state_double, state_string, environment_bool, environment_double, constant_bool, text_string };
pub const Spec = struct {
    kind: Kind,
    symbol: []const u8,
    name: []const u8,
    argument: []const u8,
    result: []const u8,
    ir_args: []const u8,
    ir_result: []const u8,
    reference: []const u8,
    ownership: []const u8,
};
pub const specs = [_]Spec{
    .{ .kind = .quad, .symbol = "zwift_native_quad", .name = "nativeQuad", .argument = "UInt64", .result = "NativeQuad", .ir_args = "i64", .ir_result = "{ i64, i64, i64, i64 }", .reference = "NativeQuad(a: value, b: value &+ 1, c: value &+ 2, d: value &+ 3)", .ownership = "trivial" },
    .{ .kind = .literal_text, .symbol = "zwift_native_text", .name = "nativeText", .argument = "UInt64", .result = "Text", .ir_args = "i64", .ir_result = "{ i64, i64, i8, ptr }", .reference = "Text(verbatim: String(value))", .ownership = "immortal ASCII literal to owned Text" },
    .{ .kind = .state_u64, .symbol = "zwift_native_state", .name = "nativeState", .argument = "UInt64", .result = "State<UInt64>", .ir_args = "i64", .ir_result = "{ i64, i64 }", .reference = "State(wrappedValue: value)", .ownership = "trivial seed; owned wrapper" },
    .{ .kind = .state_bool, .symbol = "zwift_native_state_bool", .name = "nativeStateBool", .argument = "Bool", .result = "State<Bool>", .ir_args = "i1", .ir_result = "{ i1, i64 }", .reference = "State(wrappedValue: value)", .ownership = "trivial seed; owned wrapper" },
    .{ .kind = .state_double, .symbol = "zwift_native_state_double", .name = "nativeStateDouble", .argument = "Double", .result = "State<Double>", .ir_args = "double", .ir_result = "{ double, i64 }", .reference = "State(wrappedValue: value)", .ownership = "trivial seed; d0 plus x0 result" },
    .{ .kind = .state_string, .symbol = "zwift_native_state_string", .name = "nativeStateString", .argument = "String", .result = "State<String>", .ir_args = "i64,ptr", .ir_result = "{ i64, ptr, i64 }", .reference = "State(wrappedValue: value)", .ownership = "borrowed String retained for consuming initializer" },
    .{ .kind = .environment_bool, .symbol = "zwift_native_environment", .name = "nativeEnvironment", .argument = "KeyPath<EnvironmentValues, Bool>", .result = "Environment<Bool>", .ir_args = "ptr", .ir_result = "{ i64, i8 }", .reference = "Environment(value)", .ownership = "borrowed key path retained for consuming initializer" },
    .{ .kind = .environment_double, .symbol = "zwift_native_environment_double", .name = "nativeEnvironmentDouble", .argument = "KeyPath<EnvironmentValues, Double>", .result = "Environment<Double>", .ir_args = "ptr", .ir_result = "{ i64, i8 }", .reference = "Environment(value)", .ownership = "borrowed key path retained for consuming initializer" },
    .{ .kind = .constant_bool, .symbol = "zwift_native_constant_bool", .name = "nativeConstantBool", .argument = "Bool", .result = "Binding<Bool>", .ir_args = "i1", .ir_result = "{ i64, ptr, i1 }", .reference = "Binding.constant(value)", .ownership = "owned constant binding; writes intentionally ignored" },
    .{ .kind = .text_string, .symbol = "zwift_native_text_string", .name = "nativeTextString", .argument = "String", .result = "Text", .ir_args = "i64,ptr", .ir_result = "{ i64, i64, i8, ptr }", .reference = "Text(verbatim: value)", .ownership = "borrowed String retained for consuming initializer" },
};
const state_init = "_$s7SwiftUI5StateV12wrappedValueACyxGx_tcfC";
const env_init = "_$s7SwiftUI11EnvironmentVyACyxGs7KeyPathCyAA0C6ValuesVxGcfC";
const text_init = "_$s7SwiftUI4TextV8verbatimACSS_tcfC";
fn frame(comptime symbol: []const u8, comptime size: usize, comptime body: []const u8) []const u8 {
    return std.fmt.comptimePrint(
        \\.p2align 2
        \\.globl _{s}
        \\_{s}:
        \\.cfi_startproc
        \\  sub sp, sp, #{d}
        \\  stp x29, x30, [sp, #{d}]
        \\  add x29, sp, #{d}
        \\.cfi_def_cfa w29, 16
        \\.cfi_offset w29, -16
        \\.cfi_offset w30, -8
        \\{s}
        \\  ldp x29, x30, [sp, #{d}]
        \\  add sp, sp, #{d}
        \\  ret
        \\.cfi_endproc
        \\
    , .{ symbol, symbol, size, size - 16, size - 16, body, size - 16, size });
}
fn metadata(comptime symbol: []const u8) []const u8 {
    return "  adrp x1, " ++ symbol ++ "@GOTPAGE\n  ldr x1, [x1, " ++ symbol ++ "@GOTPAGEOFF]\n";
}
fn emit(comptime s: Spec) []const u8 {
    return switch (s.kind) {
        .quad => frame(s.symbol, 64, "  mov x1, x0\n  add x0, sp, #16\n  bl _zw_abi_quad_fill\n  ldp x0, x1, [sp, #16]\n  ldp x2, x3, [sp, #32]"),
        .literal_text => frame(s.symbol, 16, "  bl _zw_abi_label\n  mov x2, #1\n  bl _$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC\n  bl " ++ text_init),
        .state_u64, .state_bool, .state_double => blk: {
            const save = switch (s.kind) {
                .state_bool => "  strb w0, [sp]\n",
                .state_double => "  str d0, [sp]\n",
                else => "  str x0, [sp]\n",
            };
            const meta = switch (s.kind) {
                .state_bool => "_$sSbN",
                .state_double => "_$sSdN",
                else => "_$ss6UInt64VN",
            };
            const result = switch (s.kind) {
                .state_bool => "  ldrb w0, [sp, #8]\n  and w0, w0, #1\n  ldr x1, [sp, #16]",
                .state_double => "  ldr d0, [sp, #8]\n  ldr x0, [sp, #16]",
                else => "  ldp x0, x1, [sp, #8]",
            };
            break :blk frame(s.symbol, 48, save ++ "  mov x0, sp\n  add x8, sp, #8\n" ++ metadata(meta) ++ "  bl " ++ state_init ++ "\n" ++ result);
        },
        .state_string => frame(s.symbol, 64, "  stp x0, x1, [sp]\n  mov x0, x1\n  bl _swift_bridgeObjectRetain\n  mov x0, sp\n  add x8, sp, #16\n" ++ metadata("_$sSSN") ++ "  bl " ++ state_init ++ "\n  ldp x0, x1, [sp, #16]\n  ldr x2, [sp, #32]"),
        .environment_bool, .environment_double => frame(s.symbol, 48, "  str x0, [sp]\n  bl _swift_retain\n  ldr x0, [sp]\n  add x8, sp, #8\n  bl " ++ env_init ++ "\n  ldr x0, [sp, #8]\n  ldrb w1, [sp, #16]\n  and w1, w1, #1"),
        .constant_bool => frame(s.symbol, 48, "  strb w0, [sp]\n  mov x0, sp\n  add x8, sp, #8\n" ++ metadata("_$sSbN") ++ "  bl _$s7SwiftUI7BindingV8constantyACyxGxFZ\n  ldp x0, x1, [sp, #8]\n  ldrb w2, [sp, #24]\n  and w2, w2, #1"),
        .text_string => frame(s.symbol, 32, "  stp x0, x1, [sp]\n  mov x0, x1\n  bl _swift_bridgeObjectRetain\n  ldp x0, x1, [sp]\n  bl " ++ text_init),
    };
}
pub fn assembly() []const u8 {
    comptime {
        @setEvalBranchQuota(100000);
        var text: []const u8 = ".text\n";
        for (specs) |s| text = text ++ emit(s);
        return text;
    }
}
pub fn declarations() []const u8 {
    comptime {
        var text: []const u8 = "// Generated by lab/abi/schema.zig. Swift calling convention, not C.\nimport SwiftUI\n@frozen public struct NativeQuad { public var a, b, c, d: UInt64 }\n";
        for (specs) |s| text = text ++ "@_silgen_name(\"" ++ s.symbol ++ "\") public func " ++ s.name ++ "(_ value: " ++ s.argument ++ ") -> " ++ s.result ++ "\n";
        return text;
    }
}
pub fn references() []const u8 {
    comptime {
        var text: []const u8 = "// Compiled as the independent swiftc lowering oracle and benchmark baseline.\nimport SwiftUI\n";
        for (specs) |s| text = text ++ "@_silgen_name(\"oracle_" ++ s.symbol ++ "\") @inline(never) public func reference_" ++ s.name ++ "(_ value: " ++ s.argument ++ ") -> " ++ s.result ++ " { " ++ s.reference ++ " }\n";
        return text;
    }
}
pub fn manifest() []const u8 {
    comptime {
        @setEvalBranchQuota(100000);
        var text: []const u8 = "{\"target\":\"" ++ platform.swift_target ++ "\",\"specializations\":[\n";
        for (specs, 0..) |s, i| {
            if (i != 0) text = text ++ ",\n";
            text = text ++ "{\"symbol\":\"" ++ s.symbol ++ "\",\"type\":\"" ++ s.result ++ "\",\"arguments\":\"" ++ s.ir_args ++ "\",\"result\":\"" ++ s.ir_result ++ "\",\"ownership\":\"" ++ s.ownership ++ "\"}";
        }
        return text ++ "\n]}\n";
    }
}
