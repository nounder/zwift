const std = @import("std");
const zwift = @import("zwift");
const objc = zwift.objc;
const AppKit = zwift.AppKit;
const Foundation = zwift.Foundation;
const WebKit = zwift.WebKit;

const cc = std.builtin.CallingConvention.c;
const Object = objc.Object;

// ── Entry point ────────────────────────────────────────────────────────

pub fn main() void {
    const pool = objc.autoreleasePoolPush();
    defer objc.autoreleasePoolPop(pool);

    const app = AppKit.NSApplication.static("sharedApplication", .{});
    _ = app.send("setActivationPolicy:", .{AppKit.NSApplication.ActivationPolicy.accessory});

    registerClasses();

    const delegate = objc.init("FloatingWebViewDelegate");
    app.send("setDelegate:", .{delegate});
    app.send("run", .{});
}

// ── ObjC class registration ────────────────────────────────────────────

fn registerClasses() void {
    const cls = objc.allocateClassPair(objc.getClass("NSObject").?, "FloatingWebViewDelegate") orelse @panic("failed");
    _ = objc.addMethod(cls, objc.sel("applicationDidFinishLaunching:"), @ptrCast(&appDidFinishLaunching), "v@:@");
    objc.registerClassPair(cls);
}

// ── Delegate ───────────────────────────────────────────────────────────

fn appDidFinishLaunching(_: Object, _: objc.Sel, _: Object) callconv(cc) void {
    buildUI();
}

// ── UI ─────────────────────────────────────────────────────────────────

fn buildUI() void {
    // NSPanel — floating, non-activating
    const style: i64 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 7); // titled|closable|miniaturizable|resizable|nonactivatingPanel
    const panel = AppKit.NSPanel.static("alloc", .{}).send("initWithContentRect:styleMask:backing:defer:", .{
        AppKit.NSRect.make(100, 100, 480, 320),
        style,
        @as(i64, 2), // buffered
        false,
    });
    panel.send("setTitle:", .{"Floating WebView"});
    panel.send("setFloatingPanel:", .{true});
    panel.send("setLevel:", .{@as(i64, 3)}); // NSFloatingWindowLevel
    panel.send("setHidesOnDeactivate:", .{false});

    // WKWebView
    const config = WebKit.WKWebViewConfiguration.static("alloc", .{}).send("init", .{});
    const webview = WebKit.WKWebView.static("alloc", .{}).send("initWithFrame:configuration:", .{
        AppKit.NSRect.make(0, 0, 480, 320),
        config,
    });

    // Load https://example.com
    const url = Foundation.NSURL.static("alloc", .{}).send("initWithString:", .{"https://example.com"});
    const request = Foundation.NSURLRequest.static("alloc", .{}).send("initWithURL:", .{url});
    _ = webview.send("loadRequest:", .{request});

    panel.send("setContentView:", .{webview.id});
    panel.send("center", .{});
    objc.send(panel, "makeKeyAndOrderFront:", void, .{@as(?*anyopaque, null)});
}
