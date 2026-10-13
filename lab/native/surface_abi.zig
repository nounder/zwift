//! Empty Root : NSViewRepresentable<NSView, Void>, with View.Body = Never.
const E = @import("emitter.zig");
const P = "_$s7SwiftUI19NSViewRepresentableP";
const defaults = .{
    .{ "identified", "19_identifiedViewTree2inAA011_IdentifiedfG0O0C4TypeQz_tF" },
    .{ "override_size", "21_overrideSizeThatFits_2in6nsViewySo6CGSizeVz_AA09_ProposedF0V0C4TypeQztF" },
    .{ "override_layout", "21_overrideLayoutTraits_3foryAA01_fG0Vz_0C4TypeQztF" },
    .{ "inputs", "24_modifyBridgedViewInputsyyAA01_gH0VzFZ" },
    .{ "invalidates", "35_invalidatesSizeOnConstraintChangesSbvgZ" },
    .{ "layout", "14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ" },
};
pub fn assembly() []const u8 {
    var requirements: []const E.Requirement = &.{
        .{ .descriptor = P ++ "AA4ViewTb", .implementation = "Lsurface_view_conformance", .tagged = true },
        .{ .descriptor = "_$s10NSViewType7SwiftUI0A13RepresentablePTl", .implementation = "Lsurface_nsview", .tagged = true },
        .{ .descriptor = "_$s11Coordinator7SwiftUI19NSViewRepresentablePTl", .implementation = "Lsurface_void", .tagged = true },
        .{ .descriptor = P ++ "04makeC07context0C4TypeQzAA0cD7ContextVyxG_tFTq", .implementation = "_zw_paint_make" },
        .{ .descriptor = P ++ "06updateC0_7contexty0C4TypeQz_AA0cD7ContextVyxGtFTq", .implementation = "_zw_paint_update" },
        .{ .descriptor = P ++ "09dismantleC0_11coordinatory0C4TypeQz_11CoordinatorQztFZTq", .implementation = "_zw_paint_dismantle" },
        .{ .descriptor = P ++ "15makeCoordinator0F0QzyFTq", .implementation = "_zw_native_empty_init" },
        .{ .descriptor = P ++ "12sizeThatFits_6nsView7contextSo6CGSizeVSgAA08ProposedI4SizeV_0C4TypeQzAA0cD7ContextVyxGtFTq", .implementation = "_zw_surface_size" },
    };
    var thunks: []const u8 = "";
    inline for (defaults) |entry| {
        requirements = requirements ++ &[_]E.Requirement{.{ .descriptor = P ++ entry[1] ++ "Tq", .implementation = "_zw_surface_" ++ entry[0] }};
        thunks = thunks ++ E.leaf("_zw_surface_" ++ entry[0], "b " ++ P ++ "AAE" ++ entry[1] ++ "\n");
    }
    return E.conformanceForType("surface", "root", "_$s7SwiftUI19NSViewRepresentable", requirements) ++ thunks ++
        ".section __TEXT,__swift5_typeref\n.p2align 1\nLsurface_view_conformance:\n.byte 255, 7\n" ++ E.relative("_zw_native_root_witness") ++ ".byte 0\n" ++
        ".p2align 1\nLsurface_nsview:\n" ++ E.bytes("So6NSViewC") ++ ".p2align 1\nLsurface_void:\n" ++ E.bytes("yt") ++
        E.leaf("_zw_native_body_witness", E.got("x0", "_$ss5NeverO7SwiftUI4ViewACWP") ++ "ret\n") ++
        // Honor proposed dimensions; provide an ideal 800x600 when unspecified.
        E.leaf("_zw_surface_size", "mov x9, #0x4089000000000000\ntst w1, #1\ncsel x0, x0, x9, eq\nmov x9, #0xc00000000000\nmovk x9, #0x4082, lsl #48\ntst w3, #1\ncsel x1, x2, x9, eq\nmov w2, #0\nret\n");
}
pub fn viewThunks() []const u8 {
    return makeThunk("_zw_native_make_view", "9_makeView4view6inputsAA01_F7OutputsVAA11_GraphValueVyxG_AA01_F6InputsVtFZ") ++
        makeThunk("_zw_native_make_list", "13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ");
}
fn makeThunk(comptime name: []const u8, comptime target: []const u8) []const u8 {
    return E.frame(name, 64, "stp x0, x1, [sp]\nstp x2, x8, [sp, #16]\nbl _zw_native_surface_witness\nmov x3, x0\nldp x0, x1, [sp]\nldp x2, x8, [sp, #16]\nbl " ++ P ++ "AAE" ++ target ++ "\n");
}
