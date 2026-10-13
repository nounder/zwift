//! Todoz — SwiftUI todo list with Zig entry point.
//!
//! Architecture: Zig owns the entry point, NSApplication, window, and menus.
//! Swift owns the SwiftUI view layer (@Observable store, Views, rendering).
//! The bridge is C-callable functions in both directions.
//!
//! See examples/todoz_swiftui/bridge.swift for the SwiftUI side.

const std = @import("std");

// ── ObjC runtime ────────────────────────────────────────────────────

const id = *anyopaque;
const SEL = *anyopaque;
const Class = *anyopaque;
const cc = std.builtin.CallingConvention.c;

extern "c" fn objc_getClass([*:0]const u8) ?Class;
extern "c" fn sel_registerName([*:0]const u8) SEL;
extern "c" fn objc_msgSend() void;
extern "c" fn objc_allocateClassPair(?Class, [*:0]const u8, usize) ?Class;
extern "c" fn objc_registerClassPair(Class) void;
extern "c" fn class_addMethod(Class, SEL, *const anyopaque, [*:0]const u8) bool;

fn MsgSendFn(comptime ReturnType: type, comptime ArgsTuple: type) type {
    const fields = @typeInfo(ArgsTuple).@"struct".fields;
    var params: [2 + fields.len]type = undefined;
    params[0] = id;
    params[1] = SEL;
    for (fields, 0..) |f, i| {
        params[2 + i] = f.type;
    }
    return @Fn(&params, &@splat(.{}), ReturnType, .{ .@"callconv" = .c });
}

fn msg(target: anytype, comptime sel_name: [*:0]const u8, args: anytype) id {
    return msgT(id, target, sel_name, args);
}

fn msgT(comptime R: type, target: anytype, comptime sel_name: [*:0]const u8, args: anytype) R {
    const T = @TypeOf(target);
    const target_id: id = switch (@typeInfo(T)) {
        .optional => target orelse unreachable,
        .pointer => @ptrCast(@constCast(target)),
        else => @compileError("msg: bad target type"),
    };
    const f: *const MsgSendFn(R, @TypeOf(args)) = @ptrCast(&objc_msgSend);
    return @call(.auto, f, .{ target_id, sel_registerName(sel_name) } ++ args);
}

fn cls(comptime name: [*:0]const u8) id {
    return @ptrCast(objc_getClass(name) orelse unreachable);
}

fn sel(comptime name: [*:0]const u8) SEL {
    return sel_registerName(name);
}

fn nsString(comptime s: [*:0]const u8) id {
    return msg(cls("NSString"), "stringWithUTF8String:", .{s});
}

const NSRect = extern struct { x: f64, y: f64, w: f64, h: f64 };
const NSSize = extern struct { width: f64, height: f64 };

// ── Swift bridge (from bridge.swift) ────────────────────────────────

extern "c" fn swiftui_store_create() void;
extern "c" fn swiftui_create_content_view() id;

// ── App state ───────────────────────────────────────────────────────

var main_window: id = undefined;

// ── ObjC callbacks ──────────────────────────────────────────────────

fn appDidFinishLaunching(_: id, _: SEL, _: id) callconv(cc) void {}

fn appShouldTerminate(_: id, _: SEL, _: id) callconv(cc) u8 {
    return 1;
}

fn registerClasses() void {
    {
        const c = objc_allocateClassPair(objc_getClass("NSObject"), "SwiftTodozAppDelegate", 0) orelse return;
        _ = class_addMethod(c, sel("applicationDidFinishLaunching:"), @ptrCast(&appDidFinishLaunching), "v@:@");
        _ = class_addMethod(c, sel("applicationShouldTerminateAfterLastWindowClosed:"), @ptrCast(&appShouldTerminate), "B@:@");
        objc_registerClassPair(c);
    }
}

// ── UI construction ─────────────────────────────────────────────────

fn buildUI() void {
    // Create the Observable store
    swiftui_store_create();

    // Window
    const alloc_win = msg(cls("NSWindow"), "alloc", .{});
    const style: u64 = 0x1 | 0x2 | 0x4 | 0x8;
    main_window = msg(alloc_win, "initWithContentRect:styleMask:backing:defer:", .{
        NSRect{ .x = 200, .y = 200, .w = 560, .h = 680 },
        style,
        @as(u64, 2),
        @as(i8, 0),
    });
    _ = msg(main_window, "setTitle:", .{nsString("Todoz")});
    _ = msg(main_window, "center", .{});
    _ = msg(main_window, "setMinSize:", .{NSSize{ .width = 440, .height = 400 }});

    // Get SwiftUI content view from bridge
    const content_view = swiftui_create_content_view();
    _ = msg(main_window, "setContentView:", .{content_view});

    _ = msg(main_window, "makeKeyAndOrderFront:", .{@as(?id, null)});
    const app = msg(cls("NSApplication"), "sharedApplication", .{});
    _ = msg(app, "activateIgnoringOtherApps:", .{@as(i8, 1)});
}

// ── Entry point ──────────────────────────────────────────────────────

pub fn main() void {
    registerClasses();

    const app = msg(cls("NSApplication"), "sharedApplication", .{});
    _ = msg(app, "setActivationPolicy:", .{@as(i64, 0)});

    setupMenu(app);

    const del = msg(msg(cls("SwiftTodozAppDelegate"), "alloc", .{}), "init", .{});
    _ = msg(app, "setDelegate:", .{del});

    buildUI();

    _ = msg(app, "run", .{});
}

fn setupMenu(app: id) void {
    const bar = msg(msg(cls("NSMenu"), "alloc", .{}), "initWithTitle:", .{nsString("")});

    { // App menu
        const item = msg(msg(cls("NSMenuItem"), "alloc", .{}), "init", .{});
        const menu = msg(msg(cls("NSMenu"), "alloc", .{}), "initWithTitle:", .{nsString("Todoz")});
        _ = msg(menu, "addItemWithTitle:action:keyEquivalent:", .{ nsString("Quit Todoz"), sel("terminate:"), nsString("q") });
        _ = msg(item, "setSubmenu:", .{menu});
        _ = msg(bar, "addItem:", .{item});
    }

    { // Edit menu
        const item = msg(msg(cls("NSMenuItem"), "alloc", .{}), "init", .{});
        const menu = msg(msg(cls("NSMenu"), "alloc", .{}), "initWithTitle:", .{nsString("Edit")});
        _ = msg(menu, "addItemWithTitle:action:keyEquivalent:", .{ nsString("Cut"), sel("cut:"), nsString("x") });
        _ = msg(menu, "addItemWithTitle:action:keyEquivalent:", .{ nsString("Copy"), sel("copy:"), nsString("c") });
        _ = msg(menu, "addItemWithTitle:action:keyEquivalent:", .{ nsString("Paste"), sel("paste:"), nsString("v") });
        _ = msg(menu, "addItemWithTitle:action:keyEquivalent:", .{ nsString("Select All"), sel("selectAll:"), nsString("a") });
        _ = msg(item, "setSubmenu:", .{menu});
        _ = msg(bar, "addItem:", .{item});
    }

    _ = msg(app, "setMainMenu:", .{bar});
}
