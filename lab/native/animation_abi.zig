//! ARM64 Swiftcc adapters. Signatures are checked against oracle/Animation.swift.
const E = @import("emitter.zig");
pub const body_type = "7SwiftUI12TimelineViewVyAA09AnimationC8ScheduleVAA6CanvasVyAA05EmptyD0VGG";
pub const canvas_type = "7SwiftUI6CanvasVyAA9EmptyViewVG";
pub fn assembly() []const u8 {
    return E.leaf("_zw_native_body_witness", "b _zw_animation_witness\n") ++
        // C(output, schedule, schedule metadata, Canvas metadata, schedule witness,
        // Canvas witness) -> Swift initializer with an indirect result in x8.
        E.function("_zw_timeline_init", "mov x8, x0\nmov x0, x1\nmov x6, x5\nmov x5, x4\nmov x4, x3\nmov x3, x2\nmov x2, #0\n" ++ E.address("x1", "_zw_timeline_content") ++
            "bl _$s7SwiftUI12TimelineViewVA2A0D0R_rlE_7contentACyxq_Gx_q_AC7ContextVyxq__GctcfC\n") ++
        E.leaf("_zw_timeline_content", "mov x0, x8\nb _zw_make_canvas\n") ++
        E.function("_zw_schedule_init", "mov x8, x0\nmov x0, #0x1111111111111111\nmovk x0, #0x3f91, lsl #48\nmov w1, #0\nmov w2, #0\nbl _$s7SwiftUI25AnimationTimelineScheduleV15minimumInterval6pausedACSdSg_SbtcfC\n") ++
        E.function("_zw_canvas_init", "mov x8, x0\nmov x4, x2\nmov w0, #0\nmov w2, #0\n" ++ E.address("x3", "_zw_canvas_renderer") ++
            "bl _$s7SwiftUI6CanvasVA2A9EmptyViewVRszrlE6opaque9colorMode21rendersAsynchronously8rendererACyAEGSb_AA014ColorRenderingH0OSbyAA15GraphicsContextVz_So6CGSizeVtctcfC\n") ++
        // The renderer's escaping context is a real Swift heap object. The
        // inner withCGContext closure borrows a stack capture only for the call.
        E.leaf("_zw_canvas_renderer", "sub sp, sp, #80\nstp x22, x21, [sp, #48]\nstp x29, x30, [sp, #64]\nadd x29, sp, #64\n" ++
            ".cfi_def_cfa w29, 16\n.cfi_offset w29, -16\n.cfi_offset w30, -8\n.cfi_offset w21, -24\n.cfi_offset w22, -32\n" ++
            "ldr d2, [x20, #16]\nldr x2, [x0]\nstp d0, d1, [sp, #16]\nstr d2, [sp, #32]\n" ++ E.address("x0", "_zw_cg_renderer") ++
            "mov x1, sp\nmov x21, #0\nbl _$s7SwiftUI15GraphicsContextV13withCGContext7contentyySo0F3RefaKXE_tKF\n" ++
            "ldp x29, x30, [sp, #64]\nldp x22, x21, [sp, #48]\nadd sp, sp, #80\nret\n") ++
        E.leaf("_zw_cg_renderer", "ldp d0, d1, [x20, #16]\nldr d2, [x20, #32]\nb _zw_animation_draw\n") ++
        E.leaf("_zw_capture_destroy", "mov x0, x20\nb _zw_capture_destroy_c\n") ++
        // Heap-local metadata, including destructor and metadata address point.
        ".section __DATA,__const\n.p2align 3\nl_capture_metadata_storage:\n.quad _zw_capture_destroy\n.quad 0\n.quad 1024\n.long 16\n.long 0\n.quad 0\n" ++
        ".globl _zw_capture_metadata\n.alt_entry _zw_capture_metadata\n.set _zw_capture_metadata, l_capture_metadata_storage + 16\n";
}
