//! Objective-C runtime bindings for Zig.
//!
//! Provides typed, ergonomic wrappers around objc_msgSend and the ObjC runtime,
//! enabling Zig code to call AppKit/Cocoa APIs directly without Swift.

const std = @import("std");
const CallingConvention = std.builtin.CallingConvention;

// The platform C calling convention
const cc = CallingConvention.c;

// ── Opaque runtime types ───────────────────────────────────────────────

pub const Class = *opaque {};
pub const Object = *opaque {};
pub const Sel = *opaque {};
pub const Imp = *const fn () callconv(cc) void;
pub const Protocol = *opaque {};

/// Semantic type aliases for method tables.
/// At runtime all are `id` (Object), but in the table they document intent
/// and enable auto-coercion (e.g. NSString args accept [*:0]const u8).
pub const NSString = Object;
pub const NSView = Object;
pub const NSColor = Object;
pub const NSFont = Object;
pub const NSImage = Object;
pub const NSImageView = Object;
pub const NSMenu = Object;
pub const NSToolbar = Object;
pub const NSToolbarItem = Object;
pub const NSArray = Object;
pub const NSAttributedString = Object;
pub const BOOL = u8; // ObjC BOOL — coercion auto-converts Zig `bool`
pub const NSInteger = i64;
pub const NSUInteger = c_ulong;
pub const CGFloat = f64;

// ── Core runtime externs ───────────────────────────────────────────────

extern "c" fn objc_getClass(name: [*:0]const u8) ?Class;
extern "c" fn sel_registerName(name: [*:0]const u8) Sel;
extern "c" fn objc_allocateClassPair(superclass: ?Class, name: [*:0]const u8, extra_bytes: usize) ?Class;
extern "c" fn objc_registerClassPair(cls: Class) void;
extern "c" fn class_addMethod(cls: Class, name: Sel, imp: Imp, types: [*:0]const u8) bool;
extern "c" fn class_addIvar(cls: Class, name: [*:0]const u8, size: usize, alignment: u8, types: ?[*:0]const u8) bool;
extern "c" fn class_addProtocol(cls: Class, protocol: Protocol) bool;
extern "c" fn objc_getProtocol(name: [*:0]const u8) ?Protocol;
extern "c" fn object_getInstanceVariable(obj: Object, name: [*:0]const u8, out_value: *?*anyopaque) ?*anyopaque;
extern "c" fn object_setInstanceVariable(obj: Object, name: [*:0]const u8, value: ?*anyopaque) ?*anyopaque;

// ── Public helpers ─────────────────────────────────────────────────────

pub fn getClass(name: [*:0]const u8) ?Class {
    return objc_getClass(name);
}

pub fn sel(name: [*:0]const u8) Sel {
    return sel_registerName(name);
}

pub fn allocateClassPair(superclass: ?Class, name: [*:0]const u8) ?Class {
    return objc_allocateClassPair(superclass, name, 0);
}

pub fn registerClassPair(cls: Class) void {
    objc_registerClassPair(cls);
}

pub fn addMethod(cls: Class, name: Sel, imp: Imp, types: [*:0]const u8) bool {
    return class_addMethod(cls, name, imp, types);
}

pub fn addIvar(cls: Class, name: [*:0]const u8, size: usize, alignment: u8, types: ?[*:0]const u8) bool {
    return class_addIvar(cls, name, size, alignment, types);
}

pub fn addProtocol(cls: Class, name: [*:0]const u8) bool {
    const proto = objc_getProtocol(name) orelse return false;
    return class_addProtocol(cls, proto);
}

pub fn getIvar(obj: Object, comptime T: type, name: [*:0]const u8) ?T {
    var out: ?*anyopaque = null;
    _ = object_getInstanceVariable(obj, name, &out);
    if (out) |ptr| {
        return @as(T, @ptrCast(@alignCast(ptr)));
    }
    return null;
}

pub fn setIvar(obj: Object, name: [*:0]const u8, value: ?*anyopaque) void {
    _ = object_setInstanceVariable(obj, name, value);
}

// ── msgSend ────────────────────────────────────────────────────────────
//
// The key challenge: objc_msgSend has a variadic C signature, but Zig
// needs to cast the function pointer to the correct type for each call.
// We use @ptrCast to reinterpret the raw function pointer.

extern "c" fn objc_msgSend() void;
extern "c" fn objc_msgSend_stret() void;

/// Send a message to an ObjC object/class.
///   const result = send(target, "selectorName:", ReturnType, .{ arg1, arg2 });
pub fn send(target: anytype, comptime selector: [*:0]const u8, comptime ReturnType: type, args: anytype) ReturnType {
    const target_ptr = objcPtr(target);
    const FnType = MsgSendFn(ReturnType, @TypeOf(args));
    const func: *const FnType = @ptrCast(&objc_msgSend);
    return @call(.auto, func, .{ target_ptr, sel(selector) } ++ args);
}

/// Get an ObjC class pointer resolved at link time — zero runtime cost.
///
/// Every ObjC class emits a linker symbol `_OBJC_CLASS_$_<ClassName>` in its
/// framework's Mach-O binary. The dynamic linker (dyld) resolves these symbols
/// at load time and writes the class pointer into the Global Offset Table (GOT).
///
/// This function uses Zig's @extern to reference that symbol directly, which
/// compiles down to a single `adrp` + `ldr` from the GOT — the same codegen
/// that Swift produces for ObjC class references. No hash table lookup, no
/// function call overhead.
///
/// Compare to `objc_getClass("NSWindow")` which does a runtime hash table
/// lookup on every call (~10-20ns). The linker approach is effectively free
/// since the pointer is already in the GOT after process launch.
///
/// Only works for classes defined in linked frameworks (AppKit, Foundation,
/// WebKit, etc). Does not work for dynamically registered classes created
/// with `objc_allocateClassPair` at runtime.
pub fn class(comptime name: [:0]const u8) Class {
    return @ptrCast(@extern(*anyopaque, .{ .name = "OBJC_CLASS_$_" ++ name }));
}

pub fn alloc(comptime T: type) Id {
    return .{ .id = send(T.class, "alloc", Object, .{}) };
}

/// Alloc+init a runtime-registered ObjC class by name.
/// For dynamically created classes (via allocateClassPair), not framework classes.
pub fn init(comptime class_name: [*:0]const u8) Object {
    return send(send(getClass(class_name).?, "alloc", Object, .{}), "init", Object, .{});
}

pub const Id = struct {
    id: Object,

    pub fn send(self: Id, comptime selector: [*:0]const u8, comptime R: type, args: anytype) R {
        const target_ptr = objcPtr(self.id);
        const FnType = MsgSendFn(R, @TypeOf(args));
        const func: *const FnType = @ptrCast(&objc_msgSend);
        return @call(.auto, func, .{ target_ptr, sel(selector) } ++ args);
    }
};

// ── NSString helpers ───────────────────────────────────────────────────

pub fn nsString(str: [*:0]const u8) Object {
    return send(class("NSString"), "stringWithUTF8String:", Object, .{str});
}

pub fn nsStringFromSlice(bytes: []const u8) Object {
    return send(class("NSString"), "stringWithUTF8String:", Object, .{bytes.ptr});
}

pub fn toZigString(ns_str: Object) ?[*:0]const u8 {
    return send(ns_str, "UTF8String", ?[*:0]const u8, .{});
}

// ── NSNumber helpers ───────────────────────────────────────────────────

pub fn nsNumberWithInt(val: c_int) Object {
    return send(class("NSNumber"), "numberWithInt:", Object, .{val});
}

pub fn nsNumberWithBool(val: bool) Object {
    const byte: u8 = if (val) 1 else 0;
    return send(class("NSNumber"), "numberWithBool:", Object, .{byte});
}

// ── NSValue helpers (for wrapping pointers) ────────────────────────────

pub fn nsValueWithPointer(ptr: *anyopaque) Object {
    return send(class("NSValue"), "valueWithPointer:", Object, .{ptr});
}

pub fn pointerFromNSValue(val: Object) ?*anyopaque {
    return send(val, "pointerValue", ?*anyopaque, .{});
}

// ── Autorelease pool ───────────────────────────────────────────────────

extern "c" fn objc_autoreleasePoolPush() ?*anyopaque;
extern "c" fn objc_autoreleasePoolPop(ctx: ?*anyopaque) void;

pub fn autoreleasePoolPush() ?*anyopaque {
    return objc_autoreleasePoolPush();
}

pub fn autoreleasePoolPop(ctx: ?*anyopaque) void {
    objc_autoreleasePoolPop(ctx);
}

// ── Typed send mixin ───────────────────────────────────────────────────
//
// Gives any struct with `obj: Object` a type-safe `.send()` method.
// A comptime selector table validates return types and argument types.
//
// Usage:
//   pub const Window = struct {
//       obj: Object,
//       pub usingnamespace Sendable(@This(), .{
//           .{ "setTitle:",      void,   .{Object} },
//           .{ "setToolbarStyle:", void, .{i64} },
//           .{ "contentView",    Object, .{} },
//           .{ "tag",            i64,    .{} },
//       });
//   };
//
//   window.send("setTitle:", .{ns_string});       // type-checked
//   window.send("setToolbarStyle:", .{@as(i64,3)});
//   const v = window.send("contentView", .{});    // returns Object
//   const t = window.send("tag", .{});             // returns i64
//
// If the selector isn't in the table → compile error.
// If arg types don't match → compile error.

/// Type-checked send. Call from a struct method like:
///   pub fn send(self: @This(), comptime selector: [*:0]const u8, args: anytype) ... {
///       return objc.typedSend(table, self.id, selector, args);
///   }
pub fn typedSend(comptime table: anytype, target: Object, comptime selector: [*:0]const u8, args: anytype) SendReturn(table, selector) {
    return typedSendFor(void, table, target, selector, args);
}

pub fn typedSendFor(comptime Cls: type, comptime table: anytype, target: Object, comptime selector: [*:0]const u8, args: anytype) SendReturnFor(Cls, table, selector) {
    const Ret = SendReturnFor(Cls, table, selector);
    const sel_s = comptime selStr(selector);
    // Implicit NSObject selectors have no table entry for arg types — they take no args
    if (Cls != void and comptime isObjcStruct(Cls) and findInTable(table, sel_s) == null) {
        const raw = send(target, selector, AbiType(Ret), .{});
        return wrapReturn(Ret, raw);
    }
    const AbiArgs = AbiArgTypes(SendArgTypes(table, selector));
    const raw = send(target, selector, AbiType(Ret), coerceArgs(AbiArgs, args));
    return wrapReturn(Ret, raw);
}

/// Type-checked class-level send. For class methods (like [NSColor systemRedColor]).
pub fn typedClassSend(comptime class_name: [*:0]const u8, comptime table: anytype, comptime selector: [*:0]const u8, args: anytype) SendReturn(table, selector) {
    return typedClassSendFor(void, class_name, table, selector, args);
}

pub fn typedClassSendFor(comptime Cls: type, comptime class_name: [*:0]const u8, comptime table: anytype, comptime selector: [*:0]const u8, args: anytype) SendReturnFor(Cls, table, selector) {
    const Ret = SendReturnFor(Cls, table, selector);
    const sel_s = comptime selStr(selector);
    const cls_ptr = class(std.mem.span(class_name));
    // Implicit NSObject selectors have no table entry for arg types — they take no args
    if (Cls != void and comptime isObjcStruct(Cls) and findInTable(table, sel_s) == null) {
        const raw = send(cls_ptr, selector, AbiType(Ret), .{});
        return wrapReturn(Ret, raw);
    }
    const AbiArgs = AbiArgTypes(SendArgTypes(table, selector));
    const raw = send(cls_ptr, selector, AbiType(Ret), coerceArgs(AbiArgs, args));
    return wrapReturn(Ret, raw);
}

/// Look up selector in a single method table. Returns the entry index or null.
fn findInTable(comptime table: anytype, comptime sel_s: []const u8) ?comptime_int {
    for (table, 0..) |entry, i| {
        if (comptime std.mem.eql(u8, selStr(entry[0]), sel_s)) {
            return i;
        }
    }
    return null;
}

/// Walk an inheritance chain of method tables to find a selector's return type.
/// For init selectors found on a parent class, returns the leaf Cls instead
/// of the parent type — since ObjC init always returns the receiver's type.
pub fn SendReturnChain(comptime Cls: type, comptime selector: [*:0]const u8) type {
    return SendReturnChainInner(Cls, Cls, selector);
}

fn SendReturnChainInner(comptime LeafCls: type, comptime Cls: type, comptime selector: [*:0]const u8) type {
    @setEvalBranchQuota(100000);
    const sel_s = comptime selStr(selector);
    if (@hasDecl(Cls, "methods")) {
        if (findInTable(Cls.methods, sel_s)) |i| {
            const ret = Cls.methods[i][1];
            // If this is an init selector and it was found on a parent,
            // return the leaf class type instead of the parent type.
            if (comptime isInitSelector(sel_s) and ret != LeafCls and isObjcStruct(ret)) {
                return LeafCls;
            }
            return ret;
        }
    }
    if (@hasDecl(Cls, "Super")) {
        return SendReturnChainInner(LeafCls, Cls.Super, selector);
    }
    // Implicit NSObject selectors — init/alloc always return Self
    if (comptime isInitSelector(sel_s) or std.mem.eql(u8, sel_s, "alloc")) {
        return LeafCls;
    }
    @compileError("Unknown selector: " ++ sel_s ++ " — not found in class or any superclass");
}

fn isInitSelector(comptime sel_s: []const u8) bool {
    return sel_s.len >= 4 and sel_s[0] == 'i' and sel_s[1] == 'n' and sel_s[2] == 'i' and sel_s[3] == 't' and (sel_s.len == 4 or sel_s[4] < 'a' or sel_s[4] > 'z');
}

/// Walk an inheritance chain to find arg types for a selector.
fn SendArgTypesChain(comptime Cls: type, comptime selector: [*:0]const u8) type {
    @setEvalBranchQuota(100000);
    const sel_s = comptime selStr(selector);
    if (@hasDecl(Cls, "methods")) {
        if (findInTable(Cls.methods, sel_s)) |i| {
            return ArgTuple(Cls.methods[i][2]);
        }
    }
    if (@hasDecl(Cls, "Super")) {
        return SendArgTypesChain(Cls.Super, selector);
    }
    // Implicit NSObject selectors take no args
    if (comptime std.mem.eql(u8, sel_s, "init") or std.mem.eql(u8, sel_s, "alloc")) {
        return ArgTuple(.{});
    }
    unreachable;
}

/// Walk an inheritance chain to find a selector, then do a typed send.
pub fn typedSendChain(comptime Cls: type, target: Object, comptime selector: [*:0]const u8, args: anytype) SendReturnChain(Cls, selector) {
    const RetType = SendReturnChain(Cls, selector);
    const ArgTypes = SendArgTypesChain(Cls, selector);
    const AbiArgs = AbiArgTypes(ArgTypes);
    const raw = send(target, selector, AbiType(RetType), coerceArgs(AbiArgs, args));
    return wrapReturn(RetType, raw);
}

// ── Unified send dispatch ───────────────────────────────────────────────
//
// Generates a single `send` function for each ObjC wrapper struct that
// works as both a class method and an instance method:
//
//   NSWindow.send("alloc", .{})                    // class method
//   window.send("setTitle:", .{"hello"})            // instance method
//   NSWindow.send("alloc", .{}).send("init", .{})  // chained
//

/// Generates instance dispatch for an ObjC wrapper struct.
/// Usage in generated code: `pub const send = objc.InstanceDispatch(@This()).invoke;`
pub fn InstanceDispatch(comptime Self: type) type {
    return struct {
        pub fn invoke(self: Self, comptime selector: [*:0]const u8, args: anytype) InstanceReturn(Self, selector) {
            return instanceSend(Self, self.id, selector, args);
        }
    };
}

/// Untyped message send — bypasses the method table.
/// Allows chaining on any typed struct for selectors not in the generated bindings.
///   obj.raw(ReturnType, "initWithHTML:options:", .{ data, opts })
pub fn RawDispatch(comptime Self: type) type {
    return struct {
        pub fn invoke(self: Self, comptime ReturnType: type, comptime selector: [*:0]const u8, args: anytype) ReturnType {
            return send(self.id, selector, ReturnType, args);
        }
    };
}

/// Generates static (class-level) dispatch for an ObjC wrapper struct.
/// Usage in generated code: `pub const static = objc.StaticDispatch(@This()).invoke;`
pub fn StaticDispatch(comptime Self: type) type {
    return struct {
        pub fn invoke(comptime selector: [*:0]const u8, args: anytype) ClassReturn(Self, selector) {
            return classSend(Self, selector, args);
        }
    };
}

/// Resolve return type for an instance send (walks Super chain + implicit init).
fn InstanceReturn(comptime Cls: type, comptime selector: [*:0]const u8) type {
    if (@hasDecl(Cls, "Super")) {
        return SendReturnChain(Cls, selector);
    }
    if (@hasDecl(Cls, "methods")) {
        return SendReturnFor(Cls, Cls.methods, selector);
    }
    // Implicit NSObject
    const sel_s = comptime selStr(selector);
    if (comptime isInitSelector(sel_s)) return Cls;
    @compileError("Unknown selector: " ++ sel_s);
}

/// Resolve return type for a class send.
fn ClassReturn(comptime Cls: type, comptime selector: [*:0]const u8) type {
    const table = if (@hasDecl(Cls, "class_methods")) Cls.class_methods else .{};
    return SendReturnFor(Cls, table, selector);
}

/// Execute an instance send with full type checking.
fn instanceSend(comptime Cls: type, target: Object, comptime selector: [*:0]const u8, args: anytype) InstanceReturn(Cls, selector) {
    const Ret = InstanceReturn(Cls, selector);
    const sel_s = comptime selStr(selector);

    // Try the chain for classes with Super
    if (@hasDecl(Cls, "Super")) {
        const ArgTypes = SendArgTypesChain(Cls, selector);
        const AbiArgs = AbiArgTypes(ArgTypes);
        const raw = send(target, selector, AbiType(Ret), coerceArgs(AbiArgs, args));
        return wrapReturn(Ret, raw);
    }

    // Single table lookup
    if (@hasDecl(Cls, "methods")) {
        if (comptime findInTable(Cls.methods, sel_s)) |_| {
            const AbiArgs = AbiArgTypes(SendArgTypes(Cls.methods, selector));
            const raw = send(target, selector, AbiType(Ret), coerceArgs(AbiArgs, args));
            return wrapReturn(Ret, raw);
        }
    }

    // Implicit NSObject (init, alloc) — no args
    const raw = send(target, selector, AbiType(Ret), .{});
    return wrapReturn(Ret, raw);
}

/// Execute a class send with full type checking.
fn classSend(comptime Cls: type, comptime selector: [*:0]const u8, args: anytype) ClassReturn(Cls, selector) {
    const Ret = ClassReturn(Cls, selector);
    const sel_s = comptime selStr(selector);
    const cls_ptr = Cls.class;
    const table = if (@hasDecl(Cls, "class_methods")) Cls.class_methods else .{};

    if (comptime findInTable(table, sel_s)) |_| {
        const AbiArgs = AbiArgTypes(SendArgTypes(table, selector));
        const raw = send(cls_ptr, selector, AbiType(Ret), coerceArgs(AbiArgs, args));
        return wrapReturn(Ret, raw);
    }

    // Implicit NSObject (alloc) — no args
    const raw = send(cls_ptr, selector, AbiType(Ret), .{});
    return wrapReturn(Ret, raw);
}

/// Look up the return type for a selector in the table. Compile error if not found.
fn selStr(comptime s: anytype) []const u8 {
    @setEvalBranchQuota(10000);
    const T = @TypeOf(s);
    if (T == [*:0]const u8) return std.mem.span(s);
    // String literal: *const [N:0]u8
    return s[0..s.len];
}

pub fn SendReturn(comptime table: anytype, comptime selector: [*:0]const u8) type {
    return SendReturnFor(void, table, selector);
}

/// Like SendReturn, but with a fallback Cls for implicit NSObject selectors (alloc, init).
pub fn SendReturnFor(comptime Cls: type, comptime table: anytype, comptime selector: [*:0]const u8) type {
    const sel_s = comptime selStr(selector);
    for (table) |entry| {
        if (comptime std.mem.eql(u8, selStr(entry[0]), sel_s)) {
            return entry[1];
        }
    }
    // Implicit NSObject selectors — return Self if Cls is known
    if (Cls != void and comptime isObjcStruct(Cls)) {
        if (comptime std.mem.eql(u8, sel_s, "alloc") or isInitSelector(sel_s)) {
            return Cls;
        }
    }
    @compileError("Unknown selector: " ++ sel_s ++ " — add it to the method table");
}

/// Look up the expected arg types for a selector. Returns a tuple struct type.
fn SendArgTypes(comptime table: anytype, comptime selector: [*:0]const u8) type {
    const sel_s = comptime selStr(selector);
    for (table) |entry| {
        if (comptime std.mem.eql(u8, selStr(entry[0]), sel_s)) {
            return ArgTuple(entry[2]);
        }
    }
    unreachable;
}

/// Convert a comptime tuple of types like .{Object, i64} into an actual tuple struct type.
fn ArgTuple(comptime type_list: anytype) type {
    const info = @typeInfo(@TypeOf(type_list)).@"struct";
    var types: [info.fields.len]type = undefined;
    for (info.fields, 0..) |_, i| {
        types[i] = type_list[i];
    }
    return @Tuple(&types);
}

/// Coerce args tuple to match expected types. Auto-converts:
/// - bool → u8 (ObjC BOOL)
/// - [*:0]const u8 → Object (NSString via nsString())
/// - enum → its integer tag (i64 or c_ulong)
/// Wrap a raw ABI return value back into its semantic type.
/// E.g. Object → NSView{.obj = raw}, ?Object → ?NSView.
fn wrapReturn(comptime Semantic: type, raw: AbiType(Semantic)) Semantic {
    if (comptime isObjcStruct(Semantic)) {
        return .{ .id = raw };
    }
    if (@typeInfo(Semantic) == .optional) {
        const Child = @typeInfo(Semantic).optional.child;
        if (comptime isObjcStruct(Child)) {
            if (raw) |obj| return .{ .id = obj };
            return null;
        }
    }
    return raw;
}

/// Check if a type is an ObjC wrapper struct (has `obj: Object` field).
fn isObjcStruct(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    return @hasField(T, "id");
}

/// Convert a semantic type from a method table to its C ABI type.
/// Wrapper structs (NSView, NSWindow, etc.) → Object, nullable wrappers → ?Object.
fn AbiType(comptime T: type) type {
    if (isObjcStruct(T)) return Object;
    if (@typeInfo(T) == .optional) {
        const Child = @typeInfo(T).optional.child;
        if (isObjcStruct(Child)) return ?Object;
    }
    return T;
}

/// Convert a full args tuple's types to ABI types.
fn AbiArgTypes(comptime Expected: type) type {
    const fields = @typeInfo(Expected).@"struct".fields;
    var types: [fields.len]type = undefined;
    for (fields, 0..) |f, i| {
        types[i] = AbiType(f.type);
    }
    return @Tuple(&types);
}

fn coerceArgs(comptime Expected: type, args: anytype) Expected {
    const exp_fields = @typeInfo(Expected).@"struct".fields;
    const arg_fields = @typeInfo(@TypeOf(args)).@"struct".fields;

    if (exp_fields.len != arg_fields.len) {
        @compileError("Wrong number of arguments: expected " ++
            std.fmt.comptimePrint("{d}", .{exp_fields.len}) ++ ", got " ++
            std.fmt.comptimePrint("{d}", .{arg_fields.len}));
    }

    var result: Expected = undefined;
    inline for (exp_fields, 0..) |field, i| {
        const val = args[i];
        const ExpType = field.type;
        const ValType = @TypeOf(val);

        if (ExpType == ValType) {
            // Exact match
            @field(result, field.name) = val;
        } else if (ValType == bool and (ExpType == u8 or ExpType == BOOL)) {
            // bool → BOOL (u8)
            @field(result, field.name) = @intFromBool(val);
        } else if (ExpType == Object and ValType == [*:0]const u8) {
            // Null-terminated string → NSString
            @field(result, field.name) = nsString(val);
        } else if (ExpType == Object and ValType == [:0]const u8) {
            // Sentinel-terminated slice → NSString
            @field(result, field.name) = nsString(val.ptr);
        } else if (ExpType == Object and comptime isStringLiteral(ValType)) {
            // String literal (*const [N:0]u8) → NSString
            @field(result, field.name) = nsString(@as([*:0]const u8, val));
        } else if ((ExpType == Object or ExpType == *anyopaque) and comptime isObjcStruct(ValType)) {
            // ObjC wrapper struct → Object/*anyopaque (extract .obj)
            @field(result, field.name) = @ptrCast(val.id);
        } else if ((ExpType == Object or ExpType == *anyopaque) and @typeInfo(ValType) == .pointer) {
            // Any pointer → Object/*anyopaque
            @field(result, field.name) = @ptrCast(@constCast(val));
        } else if (@typeInfo(ValType) == .@"enum" and (ExpType == i64 or ExpType == c_ulong)) {
            // Zig enum → integer
            @field(result, field.name) = @intFromEnum(val);
        } else if (@typeInfo(ExpType) == .@"enum" and @typeInfo(ValType) == .int) {
            // integer → Zig enum (e.g. @as(i64, 0) → ActivationPolicy)
            @field(result, field.name) = @enumFromInt(val);
        } else if (@typeInfo(ExpType) == .@"enum" and @typeInfo(ValType) == .comptime_int) {
            // comptime int → Zig enum
            @field(result, field.name) = @enumFromInt(val);
        } else if (@typeInfo(ValType) == .comptime_int) {
            // Comptime int → target integer type
            @field(result, field.name) = val;
        } else if (@typeInfo(ValType) == .int and @typeInfo(ExpType) == .int) {
            // int → int (e.g. u64 → i64)
            @field(result, field.name) = @intCast(val);
        } else if (@typeInfo(ValType) == .comptime_float) {
            // Comptime float → target float type
            @field(result, field.name) = val;
        } else if (@typeInfo(ValType) == .@"struct" and @typeInfo(ExpType) == .@"struct") {
            // Struct → struct (e.g. Size, Rect)
            @field(result, field.name) = val;
        } else if (ExpType == ?Object and comptime isObjcStruct(ValType)) {
            // ObjC wrapper struct → ?Object
            @field(result, field.name) = val.id;
        } else if (ExpType == ?Object and ValType == Object) {
            // Object → ?Object
            @field(result, field.name) = val;
        } else if (ExpType == ?Object and ValType == [*:0]const u8) {
            // Null-terminated string → ?NSString
            @field(result, field.name) = nsString(val);
        } else if (ExpType == ?Object and ValType == [:0]const u8) {
            // Sentinel-terminated slice → ?NSString
            @field(result, field.name) = nsString(val.ptr);
        } else if (ExpType == ?Object and comptime isStringLiteral(ValType)) {
            // String literal → ?NSString
            @field(result, field.name) = nsString(@as([*:0]const u8, val));
        } else if (ExpType == ?*anyopaque and comptime isObjcStruct(ValType)) {
            // ObjC wrapper struct → ?*anyopaque (protocol-typed params)
            @field(result, field.name) = val.id;
        } else if (ExpType == ?*anyopaque and ValType == Object) {
            // Object → ?*anyopaque
            @field(result, field.name) = val;
        } else if (ExpType == ?*anyopaque and @typeInfo(ValType) == .pointer) {
            // Any pointer → ?*anyopaque
            @field(result, field.name) = @ptrCast(@constCast(val));
        } else if (@typeInfo(ValType) == .optional and ExpType == ?*anyopaque) {
            // Optional → ?*anyopaque
            @field(result, field.name) = val;
        } else if (ExpType == Object and ValType == ?*anyopaque) {
            // ?*anyopaque → Object (unsafe but needed for generated bindings)
            @field(result, field.name) = @ptrCast(val.?);
        } else if (@typeInfo(ExpType) == .int and @typeInfo(ValType) == .float) {
            // float → int (for mixed type mappings in generated code)
            @field(result, field.name) = @intFromFloat(val);
        } else if (@typeInfo(ExpType) == .float and @typeInfo(ValType) == .int) {
            // int → float
            @field(result, field.name) = @floatFromInt(val);
        } else {
            @compileError("Cannot coerce " ++ @typeName(ValType) ++ " to " ++ @typeName(ExpType));
        }
    }
    return result;
}

fn isStringLiteral(comptime T: type) bool {
    // Matches *const [N:0]u8 — the type of string literals like "hello"
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .one and p.is_const and blk: {
            break :blk switch (@typeInfo(p.child)) {
                .array => |a| a.child == u8 and a.sentinel() != null,
                else => false,
            };
        },
        else => false,
    };
}

// ── Internals ──────────────────────────────────────────────────────────

/// Convert any ObjC-compatible pointer to a raw pointer for msgSend.
fn objcPtr(val: anytype) *anyopaque {
    const T = @TypeOf(val);
    if (@typeInfo(T) == .@"struct") {
        if (@hasField(T, "id")) return @ptrCast(@constCast(val.id));
    }
    return switch (@typeInfo(T)) {
        .pointer => @ptrCast(@constCast(val)),
        .optional => if (val) |v| @ptrCast(@constCast(v)) else @as(*anyopaque, @ptrFromInt(0)),
        else => @compileError("expected pointer type for objc target, got " ++ @typeName(T)),
    };
}

/// Build a function pointer type for objc_msgSend with the right return and arg types.
fn MsgSendFn(comptime ReturnType: type, comptime ArgsTuple: type) type {
    const args_info = @typeInfo(ArgsTuple).@"struct";
    const base_count = 2; // self + sel

    var params: [base_count + args_info.fields.len]type = undefined;

    // self
    params[0] = *anyopaque;
    // _cmd
    params[1] = Sel;

    // extra args
    for (args_info.fields, 0..) |field, i| {
        params[base_count + i] = field.type;
    }

    return @Fn(&params, &@splat(.{}), ReturnType, .{ .@"callconv" = cc });
}
