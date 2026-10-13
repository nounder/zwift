//! Small, bounded support for runtime-sized Swift values. No layout guesses
//! for resilient SDK structs: allocate/copy/destroy through their value witnesses.
pub const Metadata = *const anyopaque;
extern fn swift_getTypeByMangledNameInContext2([*]const u8, usize, ?Metadata, ?Metadata) ?Metadata;
extern fn swift_conformsToProtocol(Metadata, Metadata) ?Metadata;
extern fn malloc(usize) ?*anyopaque;
extern fn free(*anyopaque) void;
pub extern const @"$s7SwiftUI4ViewMp": anyopaque;
pub fn metadata(comptime mangled: []const u8) Metadata {
    return swift_getTypeByMangledNameInContext2(mangled.ptr, mangled.len, null, null) orelse @panic("Swift type lookup failed: " ++ mangled);
}
pub fn witness(m: Metadata, protocol: Metadata) Metadata {
    return swift_conformsToProtocol(m, protocol) orelse @panic("Swift conformance lookup failed");
}
pub const Witnesses = extern struct {
    buffer_copy: *const anyopaque,
    destroy: *const fn (*anyopaque, Metadata) callconv(.c) void,
    copy: *const fn (*anyopaque, *const anyopaque, Metadata) callconv(.c) *anyopaque,
    remaining: [5]*const anyopaque,
    size: usize,
    stride: usize,
    flags: u32,
    extra_inhabitants: u32,
    enum_get_tag: *const anyopaque,
    enum_project: *const anyopaque,
    enum_inject: *const fn (*anyopaque, u32, Metadata) callconv(.c) void,
};
pub fn witnesses(m: Metadata) *const Witnesses {
    return @as(*const *const Witnesses, @ptrFromInt(@intFromPtr(m) - 8)).*;
}
pub const Value = struct {
    ptr: *anyopaque,
    type: Metadata,
    pub fn alloc(m: Metadata) Value {
        if (witnesses(m).flags & 255 > 15) @panic("Swift value requires alignment beyond malloc's guarantee");
        return .{ .ptr = malloc(@max(1, witnesses(m).size)) orelse @panic("Swift value allocation failed"), .type = m };
    }
    /// For an initialized value still owned by the caller.
    pub fn deinit(self: Value) void {
        witnesses(self.type).destroy(self.ptr, self.type);
        self.freeStorage();
    }
    /// For a value consumed by a Swift initializer; do NOT destroy it twice.
    pub fn freeStorage(self: Value) void {
        free(self.ptr);
    }
    pub fn clone(self: Value) Value {
        const result = alloc(self.type);
        _ = witnesses(self.type).copy(result.ptr, self.ptr, self.type);
        return result;
    }
};
