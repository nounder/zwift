//! A bounded Swift ABI backend: empty nominal View/App structs, with specialized
//! Text, TimelineView/Canvas and NSViewRepresentable bodies. No Swift object input.
//! ARM64, Swift 5 ABI, macOS 26+. See oracle.swift and check_oracle.py.
const std = @import("std");

pub const Body = enum { text, animation, paint };
pub const App = struct { module: []const u8, root: []const u8, app: []const u8, text: []const u8 = "", body: Body = .text };

const view = "_$s7SwiftUI4View";
const app_protocol = "_$s7SwiftUI3App";
pub const Requirement = struct { descriptor: []const u8, implementation: []const u8, tagged: bool = false };
const view_requirements = [_]Requirement{
    .{ .descriptor = view ++ "P4BodyAC_AaBTn", .implementation = "Lroot_body_conformance", .tagged = true },
    .{ .descriptor = "_$s4Body7SwiftUI4ViewPTl", .implementation = "Lbody_type", .tagged = true },
    .{ .descriptor = view ++ "P05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZTq", .implementation = "_zw_native_make_view" },
    .{ .descriptor = view ++ "P05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZTq", .implementation = "_zw_native_make_list" },
    .{ .descriptor = view ++ "P14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZTq", .implementation = "_zw_native_list_count" },
    .{ .descriptor = view ++ "P4body4BodyQzvgTq", .implementation = "_zw_native_root_body" },
};
const app_requirements = [_]Requirement{
    .{ .descriptor = app_protocol ++ "P4BodyAC_AA5SceneTn", .implementation = "Lapp_body_conformance", .tagged = true },
    .{ .descriptor = "_$s4Body7SwiftUI3AppPTl", .implementation = "Lgroup_type", .tagged = true },
    .{ .descriptor = app_protocol ++ "P4body4BodyQzvgTq", .implementation = "_zw_native_app_body" },
    .{ .descriptor = app_protocol ++ "PxycfCTq", .implementation = "_zw_native_empty_init" },
};

pub fn relative(comptime target: []const u8) []const u8 {
    return ".long " ++ target ++ " - .\n";
}
pub fn address(comptime reg: []const u8, comptime symbol: []const u8) []const u8 {
    return "adrp " ++ reg ++ ", " ++ symbol ++ "@PAGE\nadd " ++ reg ++ ", " ++ reg ++ ", " ++ symbol ++ "@PAGEOFF\n";
}
pub fn got(comptime reg: []const u8, comptime symbol: []const u8) []const u8 {
    return "adrp " ++ reg ++ ", " ++ symbol ++ "@GOTPAGE\nldr " ++ reg ++ ", [" ++ reg ++ ", " ++ symbol ++ "@GOTPAGEOFF]\n";
}
pub fn leaf(comptime name: []const u8, comptime body: []const u8) []const u8 {
    return ".text\n.p2align 2\n.globl " ++ name ++ "\n" ++ name ++ ":\n.cfi_startproc\n" ++ body ++ ".cfi_endproc\n";
}
// Every non-leaf preserves x19/x20 (Swift's context/self register), frame and LR.
// The first 16 bytes remain available for outgoing stack arguments.
pub fn function(comptime name: []const u8, comptime body: []const u8) []const u8 {
    return frame(name, 48, body);
}
pub fn frame(comptime name: []const u8, comptime size: usize, comptime body: []const u8) []const u8 {
    return leaf(name, std.fmt.comptimePrint("sub sp, sp, #{d}\nstp x20, x19, [sp, #{d}]\nstp x29, x30, [sp, #{d}]\nadd x29, sp, #{d}\n", .{ size, size - 32, size - 16, size - 16 }) ++
        ".cfi_def_cfa w29, 16\n.cfi_offset w29, -16\n.cfi_offset w30, -8\n.cfi_offset w19, -24\n.cfi_offset w20, -32\n" ++ body ++
        std.fmt.comptimePrint("ldp x29, x30, [sp, #{d}]\nldp x20, x19, [sp, #{d}]\nadd sp, sp, #{d}\nret\n", .{ size - 16, size - 32, size }));
}
pub fn bytes(comptime value: []const u8) []const u8 {
    var result: []const u8 = "";
    for (value) |byte| result = result ++ std.fmt.comptimePrint(".byte {d}\n", .{byte});
    return result ++ ".byte 0\n";
}
fn identifier(comptime name: []const u8) void {
    if (name.len == 0) @compileError("Native ABI identifier cannot be empty");
    for (name, 0..) |c, i| {
        if (!(std.ascii.isAlphabetic(c) or c == '_' or (i != 0 and std.ascii.isDigit(c))))
            @compileError("Native ABI identifiers must be ASCII identifiers");
    }
}
fn nominal(comptime tag: []const u8, comptime name: []const u8) []const u8 {
    return ".section __TEXT,__const\nL" ++ tag ++ "_name:\n" ++ bytes(name) ++
        ".section __TEXT,__constg_swiftt\n.p2align 2\n.globl _zw_native_" ++ tag ++ "_descriptor\n_zw_native_" ++ tag ++ "_descriptor:\n" ++
        // Struct kind 17 | unique bit 0x40. Empty field vector starts at word 2.
        ".long 81\n" ++ relative("Lmodule") ++ relative("L" ++ tag ++ "_name") ++ relative("_zw_native_" ++ tag ++ "_metadata") ++ relative("L" ++ tag ++ "_fields") ++ ".long 0\n.long 2\n" ++
        // Metadata's address point follows its value-witness prefix. An alternate
        // entry keeps both in ONE linker atom; a normal global label can cause
        // ReleaseFast dead stripping to detach the prefix from the metadata.
        ".section __DATA,__const\n.p2align 3\nl_" ++ tag ++ "_metadata_storage:\n.quad _$sytWV\n.quad 512\n.quad _zw_native_" ++ tag ++ "_descriptor\n" ++
        ".globl _zw_native_" ++ tag ++ "_type\n.alt_entry _zw_native_" ++ tag ++ "_type\n.set _zw_native_" ++ tag ++ "_type, l_" ++ tag ++ "_metadata_storage + 8\n" ++
        ".section __TEXT,__swift5_typeref\n.p2align 1\nL" ++ tag ++ "_typeref:\n.byte 1\n" ++ relative("_zw_native_" ++ tag ++ "_descriptor") ++ ".byte 0\n" ++
        ".section __TEXT,__swift5_fieldmd,regular,no_dead_strip\n.p2align 2\nL" ++ tag ++ "_fields:\n" ++ relative("L" ++ tag ++ "_typeref") ++ ".long 0\n.short 0\n.short 12\n.long 0\n" ++
        ".section __TEXT,__swift5_types,regular,no_dead_strip\n.p2align 2\n" ++ relative("_zw_native_" ++ tag ++ "_descriptor") ++
        leaf("_zw_native_" ++ tag ++ "_metadata", address("x0", "_zw_native_" ++ tag ++ "_type") ++ "mov x1, #0\nret\n");
}
fn conformance(comptime tag: []const u8, comptime protocol: []const u8, comptime requirements: []const Requirement) []const u8 {
    return conformanceForType(tag, tag, protocol, requirements);
}
pub fn conformanceForType(comptime tag: []const u8, comptime nominal_tag: []const u8, comptime protocol: []const u8, comptime requirements: []const Requirement) []const u8 {
    var result: []const u8 = ".section __DATA,__const\n.p2align 3\nL" ++ tag ++ "_protocol:\n.quad " ++ protocol ++ "Mp\n";
    for (requirements, 0..) |r, i| result = result ++ std.fmt.comptimePrint("L{s}_requirement_{d}:\n.quad {s}\n", .{ tag, i, r.descriptor });
    result = result ++ ".zerofill __DATA,__bss,L" ++ tag ++ "_witness_cache,128,4\n" ++
        ".section __TEXT,__const\n.p2align 2\n.globl _zw_native_" ++ tag ++ "_conformance\n_zw_native_" ++ tag ++ "_conformance:\n" ++
        relative("L" ++ tag ++ "_protocol + 1") ++ relative("_zw_native_" ++ nominal_tag ++ "_descriptor") ++
        // No static witness pattern. HasResilientWitnesses | HasGenericWitnessTable.
        ".long 0\n.long 196608\n" ++ std.fmt.comptimePrint(".long {d}\n", .{requirements.len});
    for (requirements, 0..) |r, i| result = result ++ relative(std.fmt.comptimePrint("L{s}_requirement_{d} + 1", .{ tag, i })) ++ relative(r.implementation ++ (if (r.tagged) " + 1" else ""));
    // GenericWitnessTable: size=0, private size=0, requires instantiation=true,
    // no instantiator, 16-word runtime-owned private cache.
    result = result ++ ".short 0\n.short 1\n.long 0\n" ++ relative("L" ++ tag ++ "_witness_cache") ++
        ".section __TEXT,__swift5_proto,regular,no_dead_strip\n.p2align 2\n" ++ relative("_zw_native_" ++ tag ++ "_conformance");
    return result ++ leaf("_zw_native_" ++ tag ++ "_witness", address("x0", "_zw_native_" ++ tag ++ "_conformance") ++ address("x1", "_zw_native_" ++ nominal_tag ++ "_type") ++ "mov x2, #0\nb _swift_getWitnessTable\n");
}

pub fn assembly(comptime spec: App) []const u8 {
    @setEvalBranchQuota(1000000);
    identifier(spec.module);
    identifier(spec.root);
    identifier(spec.app);
    if (std.mem.eql(u8, spec.root, spec.app)) @compileError("App and View need distinct type names");
    if (!std.unicode.utf8ValidateSlice(spec.text)) @compileError("Text must be valid UTF-8");
    if (spec.text.len > 65535) @compileError("Native literal Text currently supports at most 65535 UTF-8 bytes");
    const ascii = for (spec.text) |c| {
        if (c >= 128) break false;
    } else true;
    return ".section __TEXT,__const\nLmodule_name:\n" ++ bytes(spec.module) ++ "Lmessage:\n" ++ bytes(spec.text) ++
        ".section __TEXT,__constg_swiftt\n.p2align 2\nLmodule:\n.long 0\n.long 0\n" ++ relative("Lmodule_name") ++
        nominal("root", spec.root) ++ nominal("app", spec.app) ++
        conformance("root", view, &view_requirements) ++ conformance("app", app_protocol, &app_requirements) ++
        ".section __DATA,__const\n.p2align 3\nLtext_descriptor:\n.quad _$s7SwiftUI4TextVMn\nLgroup_descriptor:\n.quad _$s7SwiftUI11WindowGroupVMn\n" ++
        ".section __TEXT,__swift5_typeref\n.p2align 1\nLbody_type:\n" ++ bytes(switch (spec.body) {
        .text => "7SwiftUI4TextV",
        .animation => @import("animation_abi.zig").body_type,
        .paint => "s5NeverO",
    }) ++
        ".p2align 1\nLgroup_type:\n.byte 2\n" ++ relative("Lgroup_descriptor") ++ ".byte 121\n.byte 1\n" ++ relative("_zw_native_root_descriptor") ++ ".byte 71\n.byte 0\n" ++
        ".p2align 1\nLroot_body_conformance:\n.byte 255, 7\n" ++ relative("_zw_native_body_witness") ++ ".byte 0\n" ++
        ".p2align 1\nLapp_body_conformance:\n.byte 255, 7\n" ++ relative("_zw_native_group_witness") ++ ".byte 0\n" ++
        (switch (spec.body) {
            .text => leaf("_zw_native_body_witness", got("x0", "_$s7SwiftUI4TextVAA4ViewAAWP") ++ "ret\n"),
            .animation => @import("animation_abi.zig").assembly(),
            .paint => @import("surface_abi.zig").assembly(),
        }) ++
        function("_zw_native_group_metadata", "bl _zw_native_root_witness\nmov x2, x0\n" ++ address("x1", "_zw_native_root_type") ++ "mov x0, #0\nbl _$s7SwiftUI11WindowGroupVMa\n") ++
        function("_zw_native_group_witness", "bl _zw_native_group_metadata\nmov x1, x0\n" ++ got("x0", "_$s7SwiftUI11WindowGroupVyxGAA5SceneAAMc") ++ "mov x2, #0\nbl _swift_getWitnessTable\n") ++
        (if (spec.body == .paint) @import("surface_abi.zig").viewThunks() else leaf("_zw_native_make_view", "b " ++ view ++ "PAAE05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZ\n") ++
            leaf("_zw_native_make_list", "b " ++ view ++ "PAAE05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZ\n")) ++
        function("_zw_native_list_count", "bl " ++ view ++ "PAAE14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZ\nand w1, w1, #1\n") ++
        // A protocol body getter returns indirectly in x8, unlike concrete Text.
        (switch (spec.body) {
            .animation => leaf("_zw_native_root_body", "mov x0, x8\nb _zw_animation_body\n"),
            .paint => leaf("_zw_native_root_body", "brk #1\n"),
            .text => function("_zw_native_root_body", "mov x19, x8\nbl _zw_native_note_root\n" ++ address("x0", "Lmessage") ++ std.fmt.comptimePrint("mov x1, #{d}\nmov x2, #{d}\n", .{ spec.text.len, @intFromBool(ascii) }) ++
                "bl _$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC\nbl _$s7SwiftUI4TextV8verbatimACSS_tcfC\nstp x0, x1, [x19]\nand w2, w2, #1\nstrb w2, [x19, #16]\nstr x3, [x19, #24]\n"),
        }) ++
        leaf("_zw_native_empty_init", "ret\n") ++
        // WindowGroup's escaping () -> Root closure has no captures and Root is
        // empty. The last two generic arguments are stack-passed, not x8/x9.
        function("_zw_native_app_body", "mov x19, x8\nbl _zw_native_note_app\nbl _zw_native_root_witness\n" ++ address("x9", "_zw_native_root_type") ++ "stp x9, x0, [sp]\n" ++
            address("x6", "_zw_native_empty_init") ++ "mov x7, #0\nmov x8, x19\nmov x0, #0\nmov x1, #0\nmov x2, #0\nmov x3, #0\nmov x4, #0\nmov x5, #0\nbl _$s7SwiftUI11WindowGroupV2id5title11lazyContentACyxGSSSg_AA4TextVSgxyctcfC\n") ++
        function("_zw_native_app_main", "bl _zw_native_app_witness\nmov x1, x0\n" ++ address("x0", "_zw_native_app_type") ++ "mov x20, x0\nbl _$s7SwiftUI3AppPAAE4mainyyFZ\n") ++
        // Swift's entry record points at the actual C main emitted by Zig.
        ".section __TEXT,__swift5_entry,regular,no_dead_strip\n.p2align 2\n" ++ relative("_main") ++ ".long 1\n" ++
        // dyld/ObjC must recognize this image as containing stable Swift ABI.
        ".section __DATA,__objc_imageinfo,regular,no_dead_strip\n.p2align 2\n.long 0\n.long 1792\n.text\n";
}
