const std = @import("std");
const zwift = @import("zwift");
const objc = zwift.objc;
const AppKit = zwift.AppKit;
const Foundation = zwift.Foundation;

const cc = std.builtin.CallingConvention.c;
const Object = objc.Object;

pub fn main() void {
    const pool = objc.autoreleasePoolPush();
    defer objc.autoreleasePoolPop(pool);

    const app = AppKit.NSApplication.static("sharedApplication", .{});
    _ = app.send("setActivationPolicy:", .{AppKit.NSApplication.ActivationPolicy.regular});

    registerClasses();

    const delegate = objc.init("HTMLTextViewDelegate");
    app.send("setDelegate:", .{delegate});
    app.send("run", .{});
}

fn registerClasses() void {
    const cls = objc.allocateClassPair(objc.getClass("NSObject").?, "HTMLTextViewDelegate") orelse @panic("failed");
    _ = objc.addMethod(cls, objc.sel("applicationDidFinishLaunching:"), @ptrCast(&appDidFinishLaunching), "v@:@");
    _ = objc.addMethod(cls, objc.sel("applicationShouldTerminateAfterLastWindowClosed:"), @ptrCast(&appShouldTerminate), "B@:@");
    objc.registerClassPair(cls);
}

fn appDidFinishLaunching(_: Object, _: objc.Sel, _: Object) callconv(cc) void {
    buildUI();
}
fn appShouldTerminate(_: Object, _: objc.Sel, _: Object) callconv(cc) u8 {
    return 1;
}

fn buildUI() void {
    const window = AppKit.NSWindow.static("alloc", .{}).send("initWithContentRect:styleMask:backing:defer:", .{
        AppKit.NSRect.make(200, 200, 600, 500),
        @as(i64, (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3)),
        @as(i64, 2),
        false,
    });
    window.send("setTitle:", .{"HTML in NSTextView"});
    window.send("center", .{});

    // Scroll view + text view
    const scroll = AppKit.NSScrollView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 600, 500)});
    scroll.send("setHasVerticalScroller:", .{true});
    scroll.send("setAutohidesScrollers:", .{true});

    const text_view = AppKit.NSTextView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 600, 500)});
    _ = text_view.send("setEditable:", .{false});
    _ = text_view.send("setRichText:", .{true});
    _ = text_view.send("setTextContainerInset:", .{AppKit.NSSize{ .width = 16, .height = 16 }});

    // HTML string with styled tables, links, lists
    const html =
        \\<html><body style="font-family: -apple-system, Helvetica Neue; font-size: 13px; color: #222;">
        \\
        \\<h2 style="color: #1a1a2e;">Styled HTML in NSTextView</h2>
        \\
        \\<p>This is <b>bold</b>, <i>italic</i>, <u>underlined</u>, and
        \\<span style="color: #e94560;">colored text</span> with
        \\<span style="background-color: #ffffcc; padding: 2px 4px;">highlighted background</span>.</p>
        \\
        \\<h3 style="color: #0f3460;">Links</h3>
        \\<p><a href="https://example.com" style="color: #e94560; font-weight: bold;">Styled link</a> —
        \\<a href="https://apple.com">Default link</a></p>
        \\
        \\<h3 style="color: #0f3460;">Styled Table</h3>
        \\<table border="1" cellpadding="8" cellspacing="0" style="border-collapse: collapse; width: 100%;">
        \\<tr style="background-color: #1a1a2e; color: white;">
        \\  <th style="text-align: left;">Component</th>
        \\  <th style="text-align: right;">Memory</th>
        \\  <th style="text-align: right;">CPU</th>
        \\</tr>
        \\<tr style="background-color: #f5f5f5;">
        \\  <td>Main process</td>
        \\  <td style="text-align: right; font-family: Menlo; color: #e94560;">30 MB</td>
        \\  <td style="text-align: right; font-family: Menlo;">0.0%</td>
        \\</tr>
        \\<tr>
        \\  <td>WebContent</td>
        \\  <td style="text-align: right; font-family: Menlo; color: #e94560;">15 MB</td>
        \\  <td style="text-align: right; font-family: Menlo;">0.0%</td>
        \\</tr>
        \\<tr style="background-color: #f5f5f5;">
        \\  <td>GPU</td>
        \\  <td style="text-align: right; font-family: Menlo; color: #e94560;">12 MB</td>
        \\  <td style="text-align: right; font-family: Menlo;">0.0%</td>
        \\</tr>
        \\<tr style="background-color: #1a1a2e; color: #e94560; font-weight: bold;">
        \\  <td>Total</td>
        \\  <td style="text-align: right; font-family: Menlo;">63 MB</td>
        \\  <td style="text-align: right; font-family: Menlo;">0.0%</td>
        \\</tr>
        \\</table>
        \\
        \\<h3 style="color: #0f3460;">Lists</h3>
        \\<ul>
        \\  <li>Unordered item <span style="color: #888;">(with styled span)</span></li>
        \\  <li style="color: #e94560;">Red list item</li>
        \\  <li><b>Bold item</b> with <i>italic</i></li>
        \\</ul>
        \\<ol>
        \\  <li>First ordered</li>
        \\  <li>Second ordered</li>
        \\</ol>
        \\
        \\<h3 style="color: #0f3460;">Blockquote</h3>
        \\<blockquote style="border-left: 3px solid #ccc; margin-left: 0; padding-left: 12px; color: #666;">
        \\This is a blockquote with <b>formatting</b> inside.
        \\</blockquote>
        \\
        \\</body></html>
    ;

    // NSAttributedString from HTML
    const html_nsstr = objc.nsString(html);
    const html_data = objc.send(html_nsstr, "dataUsingEncoding:", Object, .{@as(c_ulong, 4)}); // NSUTF8StringEncoding = 4
    const doc_type_key = objc.nsString("NSDocumentTypeDocumentAttribute");
    const html_type_val = objc.nsString("NSHTML");
    const keys = [_]Object{doc_type_key};
    const vals = [_]Object{html_type_val};
    const opts = objc.send(Foundation.NSDictionary.class, "dictionaryWithObjects:forKeys:count:", Object, .{
        @as([*]const Object, &vals),
        @as([*]const Object, &keys),
        @as(c_ulong, 1),
    });

    const attr_str = objc.alloc(Foundation.NSAttributedString).send("initWithHTML:options:documentAttributes:", Object, .{
        html_data,
        opts,
        @as(?*?*anyopaque, null),
    });

    // Set on text view
    const text_storage = objc.send(text_view, "textStorage", Object, .{});
    objc.send(text_storage, "setAttributedString:", void, .{attr_str});

    scroll.send("setDocumentView:", .{text_view.id});
    window.send("setContentView:", .{scroll.id});
    objc.send(window, "makeKeyAndOrderFront:", void, .{@as(?*anyopaque, null)});
    AppKit.NSApplication.static("sharedApplication", .{}).send("activateIgnoringOtherApps:", .{true});
}
