//! No Swift compilation, generated Swift source, or Swift application objects.
const emitter = @import("emitter.zig");
const probe = @import("probe.zig");
comptime {
    if (@import("builtin").cpu.arch != .aarch64 or @import("builtin").os.tag != .macos)
        @compileError("Native Swift ABI backend currently supports Apple ARM64 only");
    asm (emitter.assembly(@import("program.zig").app));
}
extern fn zw_native_app_main() callconv(.c) void;
export fn zw_native_note_root() void {
    probe.root();
}
export fn zw_native_note_app() void {
    probe.app();
}

pub fn main() void {
    switch (@import("program.zig").app.body) {
        .animation => @import("animation.zig").install(),
        .paint => @import("paint.zig").install(),
        .text => {},
    }
    probe.install();
    zw_native_app_main();
}
