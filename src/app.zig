//! A macOS todo app built entirely in Zig.
//!
//! Uses AppKit via Objective-C runtime calls. No Swift, no Xcode.
//! Matches the macOS 26 Tahoe design with NSToolbar glass effect.

const std = @import("std");
const objc = @import("objc.zig");
const AppKit = @import("AppKit.zig");
const Foundation = @import("Foundation.zig");

const cc = std.builtin.CallingConvention.c;
const Object = objc.Object;

// ── Todoz types & state ──────────────────────────────────────────────────

const max_todos = 256;
const max_title_len = 256;

const Todoz = struct {
    id: u64,
    title: [max_title_len]u8,
    title_len: u32,
    completed: bool,
};

var todos: [max_todos]Todoz = undefined;
var todo_count: u32 = 0;
var next_id: u64 = 1;

fn addTodozItem(title_ptr: [*]const u8, title_len: u32) u64 {
    if (todo_count >= max_todos) return 0;
    if (title_len == 0 or title_len > max_title_len) return 0;

    const id = next_id;
    next_id += 1;

    var t: Todoz = .{
        .id = id,
        .title = std.mem.zeroes([max_title_len]u8),
        .title_len = title_len,
        .completed = false,
    };
    @memcpy(t.title[0..title_len], title_ptr[0..title_len]);

    todos[todo_count] = t;
    todo_count += 1;
    return id;
}

fn removeTodozItem(id: u64) bool {
    for (0..todo_count) |i| {
        if (todos[i].id == id) {
            var j = i;
            while (j + 1 < todo_count) : (j += 1) {
                todos[j] = todos[j + 1];
            }
            todo_count -= 1;
            return true;
        }
    }
    return false;
}

fn toggleTodozItem(id: u64) bool {
    for (0..todo_count) |i| {
        if (todos[i].id == id) {
            todos[i].completed = !todos[i].completed;
            return true;
        }
    }
    return false;
}

fn getTodozItem(index: u32) ?*const Todoz {
    if (index >= todo_count) return null;
    return &todos[index];
}

fn clearCompletedItems() u32 {
    var removed: u32 = 0;
    var i: u32 = 0;
    while (i < todo_count) {
        if (todos[i].completed) {
            var j = i;
            while (j + 1 < todo_count) : (j += 1) {
                todos[j] = todos[j + 1];
            }
            todo_count -= 1;
            removed += 1;
        } else {
            i += 1;
        }
    }
    return removed;
}

fn countCompleted() u32 {
    var count: u32 = 0;
    for (0..todo_count) |i| {
        if (todos[i].completed) count += 1;
    }
    return count;
}

fn countPending() u32 {
    return todo_count - countCompleted();
}

// ── App state ──────────────────────────────────────────────────────────

var main_window: AppKit.NSWindow = undefined;
var todo_list_stack: AppKit.NSStackView = undefined;
var input_field: AppKit.NSTextField = undefined;
var filter_seg: AppKit.NSSegmentedControl = undefined;
var scroll_view: AppKit.NSScrollView = undefined;
var empty_container: AppKit.NSStackView = undefined;
var toolbar_delegate_inst: Object = undefined;

// ── Entry point ────────────────────────────────────────────────────────

pub fn main() void {
    const pool = objc.autoreleasePoolPush();
    defer objc.autoreleasePoolPop(pool);

    const app = AppKit.NSApplication.static("sharedApplication", .{});
    _ = app.send("setActivationPolicy:", .{AppKit.NSApplication.ActivationPolicy.regular});

    setupMenu(app);
    registerAllClasses();

    const delegate_inst = objc.init("TodozAppDelegate");
    app.send("setDelegate:", .{delegate_inst});
    app.send("run", .{});
}

// ── Menu bar ───────────────────────────────────────────────────────────

fn setupMenu(app: AppKit.NSApplication) void {
    const bar = AppKit.NSMenu.static("alloc", .{}).send("initWithTitle:", .{""});

    { // App menu
        const item = AppKit.NSMenuItem.static("alloc", .{}).send("init", .{});
        const menu = AppKit.NSMenu.static("alloc", .{}).send("initWithTitle:", .{"Todoz"});
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "About Todoz", objc.sel("orderFrontStandardAboutPanel:"), "" });
        menu.send("addItem:", .{AppKit.NSMenuItem.static("separatorItem", .{})});
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Hide Todoz", objc.sel("hide:"), "h" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Hide Others", objc.sel("hideOtherApplications:"), "" });
        menu.send("addItem:", .{AppKit.NSMenuItem.static("separatorItem", .{})});
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Quit Todoz", objc.sel("terminate:"), "q" });
        item.send("setSubmenu:", .{menu.id});
        bar.send("addItem:", .{item.id});
    }

    { // Edit menu
        const item = AppKit.NSMenuItem.static("alloc", .{}).send("init", .{});
        const menu = AppKit.NSMenu.static("alloc", .{}).send("initWithTitle:", .{"Edit"});
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Undo", objc.sel("undo:"), "z" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Redo", objc.sel("redo:"), "Z" });
        menu.send("addItem:", .{AppKit.NSMenuItem.static("separatorItem", .{})});
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Cut", objc.sel("cut:"), "x" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Copy", objc.sel("copy:"), "c" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Paste", objc.sel("paste:"), "v" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Select All", objc.sel("selectAll:"), "a" });
        item.send("setSubmenu:", .{menu.id});
        bar.send("addItem:", .{item.id});
    }

    { // Window menu
        const item = AppKit.NSMenuItem.static("alloc", .{}).send("init", .{});
        const menu = AppKit.NSMenu.static("alloc", .{}).send("initWithTitle:", .{"Window"});
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Close", objc.sel("performClose:"), "w" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Minimize", objc.sel("performMiniaturize:"), "m" });
        _ = menu.send("addItemWithTitle:action:keyEquivalent:", .{ "Zoom", objc.sel("performZoom:"), "" });
        item.send("setSubmenu:", .{menu.id});
        bar.send("addItem:", .{item.id});
        app.send("setWindowsMenu:", .{menu.id});
    }

    app.send("setMainMenu:", .{bar.id});
}

// ── ObjC class registration ────────────────────────────────────────────

fn registerAllClasses() void {
    { // App delegate
        const cls = objc.allocateClassPair(objc.class("NSObject"), "TodozAppDelegate") orelse @panic("failed");
        _ = objc.addMethod(cls, objc.sel("applicationDidFinishLaunching:"), @ptrCast(&appDidFinishLaunching), "v@:@");
        _ = objc.addMethod(cls, objc.sel("applicationShouldTerminateAfterLastWindowClosed:"), @ptrCast(&appShouldTerminate), "B@:@");
        objc.registerClassPair(cls);
    }
    {
        const cls = objc.allocateClassPair(objc.class("NSObject"), "TodozInputDelegate") orelse return;
        _ = objc.addMethod(cls, objc.sel("control:textView:doCommandBySelector:"), @ptrCast(&inputDoCommand), "B@:@@:");
        _ = objc.addMethod(cls, objc.sel("addTodoz:"), @ptrCast(&addTodozAction), "v@:@");
        objc.registerClassPair(cls);
    }
    {
        const cls = objc.allocateClassPair(objc.class("NSObject"), "TodozActionHandler") orelse return;
        _ = objc.addMethod(cls, objc.sel("clearCompleted:"), @ptrCast(&clearCompletedAction), "v@:@");
        _ = objc.addMethod(cls, objc.sel("toggleTodoz:"), @ptrCast(&toggleTodozAction), "v@:@");
        _ = objc.addMethod(cls, objc.sel("removeTodoz:"), @ptrCast(&removeTodozAction), "v@:@");
        _ = objc.addMethod(cls, objc.sel("filterChanged:"), @ptrCast(&filterChangedAction), "v@:@");
        objc.registerClassPair(cls);
    }
    {
        const cls = objc.allocateClassPair(objc.class("NSObject"), "TodozToolbarDelegate") orelse return;
        _ = objc.addMethod(cls, objc.sel("toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:"), @ptrCast(&toolbarItemForIdentifier), "@36@0:8@16@24B32");
        _ = objc.addMethod(cls, objc.sel("toolbarAllowedItemIdentifiers:"), @ptrCast(&toolbarAllowedIdentifiers), "@24@0:8@16");
        _ = objc.addMethod(cls, objc.sel("toolbarDefaultItemIdentifiers:"), @ptrCast(&toolbarDefaultIdentifiers), "@24@0:8@16");
        objc.registerClassPair(cls);
    }
    {
        const cls = objc.allocateClassPair(objc.class("NSClipView"), "TodozFlippedClipView") orelse return;
        _ = objc.addMethod(cls, objc.sel("isFlipped"), @ptrCast(&flippedClipIsFlipped), "B@:");
        objc.registerClassPair(cls);
    }
}

// ── Delegate callbacks ─────────────────────────────────────────────────

fn appDidFinishLaunching(_: Object, _: objc.Sel, _: Object) callconv(cc) void {
    buildUI();
}
fn appShouldTerminate(_: Object, _: objc.Sel, _: Object) callconv(cc) u8 {
    return 1;
}
fn flippedClipIsFlipped(_: Object, _: objc.Sel) callconv(cc) u8 {
    return 1;
}

// ── Toolbar ────────────────────────────────────────────────────────────

const tb_filter = "org.nounder.todoz.filter";

fn toolbarItemForIdentifier(_: Object, _: objc.Sel, _: Object, ident: Object, _: u8) callconv(cc) ?Object {
    const ident_str = objc.toZigString(ident) orelse return null;
    const ident_slice = std.mem.span(ident_str);

    if (std.mem.eql(u8, ident_slice, tb_filter)) {
        const item = AppKit.NSToolbarItem.static("alloc", .{}).send("initWithItemIdentifier:", .{ident});
        const handler = objc.init("TodozActionHandler");

        filter_seg = AppKit.NSSegmentedControl.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 24)});
        filter_seg.send("setSegmentCount:", .{3});
        filter_seg.send("setLabel:forSegment:", .{ "All", 0 });
        filter_seg.send("setLabel:forSegment:", .{ "Pending", 1 });
        filter_seg.send("setLabel:forSegment:", .{ "Completed", 2 });
        filter_seg.send("setSelectedSegment:", .{0});
        filter_seg.send("setSegmentStyle:", .{0});
        filter_seg.send("setTarget:", .{handler});
        filter_seg.send("setAction:", .{objc.sel("filterChanged:")});

        item.send("setView:", .{filter_seg.id});
        return item.id;
    }

    return null;
}

fn toolbarAllowedIdentifiers(_: Object, _: objc.Sel, _: Object) callconv(cc) Object {
    return AppKit.nsArray(&.{objc.nsString(tb_filter)});
}

fn toolbarDefaultIdentifiers(_: Object, _: objc.Sel, _: Object) callconv(cc) Object {
    return AppKit.nsArray(&.{
        objc.nsString(AppKit.NSToolbarItemIdentifier.flexibleSpace),
        objc.nsString(tb_filter),
        objc.nsString(AppKit.NSToolbarItemIdentifier.flexibleSpace),
    });
}

// ── UI construction ────────────────────────────────────────────────────

fn buildUI() void {
    const style = AppKit.NSWindow.StyleMask;
    main_window = AppKit.NSWindow.static("alloc", .{}).send("initWithContentRect:styleMask:backing:defer:", .{
        AppKit.NSRect.make(200, 200, 560, 680),
        style.titled | style.closable | style.miniaturizable | style.resizable,
        AppKit.NSWindow.BackingStoreType.buffered,
        false,
    });
    main_window.send("setTitle:", .{"Todoz"});
    main_window.send("center", .{});
    main_window.send("setMinSize:", .{AppKit.NSSize{ .width = 440, .height = 400 }});
    main_window.send("setSubtitle:", .{"0 pending \xc2\xb7 0 done"});

    { // Toolbar
        const toolbar = AppKit.NSToolbar.static("alloc", .{}).send("initWithIdentifier:", .{"org.nounder.todoz.toolbar"});
        toolbar_delegate_inst = objc.init("TodozToolbarDelegate");
        toolbar.send("setDelegate:", .{toolbar_delegate_inst});
        toolbar.send("setDisplayMode:", .{AppKit.NSToolbar.DisplayMode.iconOnly});
        main_window.send("setToolbar:", .{toolbar.id});
        main_window.send("setToolbarStyle:", .{AppKit.NSWindow.ToolbarStyle.unified});
    }

    const root = AppKit.NSStackView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 0)});
    root.send("setOrientation:", .{AppKit.NSUserInterfaceLayoutOrientation.vertical});
    root.send("setSpacing:", .{0});

    { // Input bar
        input_field = AppKit.NSTextField.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 200, 24)});
        input_field.send("setPlaceholderString:", .{"What needs to be done?"});
        input_field.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        objc.send(input_field.id, "setAccessibilityLabel:", void, .{objc.nsString("New todo title")});
        input_field.send("setFont:", .{AppKit.NSFont.static("systemFontOfSize:", .{13})});
        input_field.send("setContentHuggingPriority:forOrientation:", .{ 249, 0 });

        const del = objc.init("TodozInputDelegate");
        input_field.send("setDelegate:", .{del});

        const bar = AppKit.NSStackView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 0)});
        bar.send("setOrientation:", .{AppKit.NSUserInterfaceLayoutOrientation.horizontal});
        bar.send("setSpacing:", .{10});
        bar.send("setEdgeInsets:", .{AppKit.NSEdgeInsets{ .top = 10, .left = 16, .bottom = 10, .right = 16 }});
        bar.send("addArrangedSubview:", .{input_field.id});
        root.send("addArrangedSubview:", .{bar.id});
    }

    { // Separator
        const sep = AppKit.NSBox.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 1)});
        sep.send("setBoxType:", .{2});
        sep.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        root.send("addArrangedSubview:", .{sep.id});
    }

    { // Scroll view + todo list
        scroll_view = AppKit.NSScrollView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 0)});
        scroll_view.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        scroll_view.send("setHasVerticalScroller:", .{true});
        scroll_view.send("setAutohidesScrollers:", .{true});
        scroll_view.send("setDrawsBackground:", .{false});

        todo_list_stack = AppKit.NSStackView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 0)});
        todo_list_stack.send("setOrientation:", .{AppKit.NSUserInterfaceLayoutOrientation.vertical});
        todo_list_stack.send("setSpacing:", .{0});

        const fclip = objc.send(objc.send(objc.getClass("TodozFlippedClipView").?, "alloc", Object, .{}), "initWithFrame:", Object, .{AppKit.NSRect.make(0, 0, 0, 0)});
        scroll_view.send("setContentView:", .{fclip});
        scroll_view.send("setDocumentView:", .{todo_list_stack.id});

        todo_list_stack.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        const clip_view = scroll_view.send("contentView", .{});
        AppKit.NSLayoutConstraint.pinWidthEqual(todo_list_stack.id, clip_view.id);

        root.send("addArrangedSubview:", .{scroll_view.id});
        scroll_view.send("setContentHuggingPriority:forOrientation:", .{ 249, 1 });
    }

    { // Empty state
        empty_container = AppKit.NSStackView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 0)});
        empty_container.send("setOrientation:", .{AppKit.NSUserInterfaceLayoutOrientation.vertical});
        empty_container.send("setSpacing:", .{6});
        empty_container.send("setEdgeInsets:", .{AppKit.NSEdgeInsets{ .top = 60, .left = 60, .bottom = 60, .right = 60 }});
        empty_container.send("setAlignment:", .{9}); // centerX

        const img = AppKit.NSImage.static("imageWithSystemSymbolName:accessibilityDescription:", .{ "checkmark.circle", "No todos" });
        const icon: AppKit.NSImageView = .{ .id = AppKit.NSImageView.static("imageViewWithImage:", .{img}) };
        icon.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        icon.send("setContentTintColor:", .{AppKit.NSColor.static("secondaryLabelColor", .{})});
        icon.send("setSymbolConfiguration:", .{AppKit.NSImageSymbolConfiguration.static("configurationWithPointSize:weight:", .{ 36.0, 0.0 })});

        const title: AppKit.NSTextField = .{ .id = AppKit.NSTextField.static("labelWithString:", .{"No Todos Yet"}) };
        title.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        title.send("setFont:", .{AppKit.NSFont.static("boldSystemFontOfSize:", .{17})});
        title.send("setTextColor:", .{AppKit.NSColor.static("secondaryLabelColor", .{})});
        title.send("setAlignment:", .{2});
        title.send("setContentCompressionResistancePriority:forOrientation:", .{ 999, 0 });

        const hint: AppKit.NSTextField = .{ .id = AppKit.NSTextField.static("labelWithString:", .{"Add one above to get started."}) };
        hint.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        hint.send("setFont:", .{AppKit.NSFont.static("systemFontOfSize:", .{13})});
        hint.send("setTextColor:", .{AppKit.NSColor.static("tertiaryLabelColor", .{})});
        hint.send("setAlignment:", .{2});
        hint.send("setContentCompressionResistancePriority:forOrientation:", .{ 999, 0 });

        empty_container.send("addArrangedSubview:", .{icon.id});
        empty_container.send("addArrangedSubview:", .{title.id});
        empty_container.send("addArrangedSubview:", .{hint.id});
    }

    // Set as content view
    root.send("setTranslatesAutoresizingMaskIntoConstraints:", .{true});
    main_window.send("setContentView:", .{root.id});

    // Pin scroll view width to root
    AppKit.NSLayoutConstraint.pinWidthEqual(scroll_view.id, root.id);

    refreshTodozList();
    objc.send(main_window.id, "makeKeyAndOrderFront:", void, .{@as(?Object, null)});
    AppKit.NSApplication.static("sharedApplication", .{}).send("activateIgnoringOtherApps:", .{true});
}

// ── Actions ────────────────────────────────────────────────────────────

fn inputDoCommand(_: Object, _: objc.Sel, _: Object, _: Object, sel_cmd: objc.Sel) callconv(cc) u8 {
    if (@intFromPtr(sel_cmd) == @intFromPtr(objc.sel("insertNewline:"))) {
        addTodoz();
        return 1;
    }
    return 0;
}
fn addTodozAction(_: Object, _: objc.Sel, _: Object) callconv(cc) void {
    addTodoz();
}

fn addTodoz() void {
    const raw = objc.toZigString(input_field.send("stringValue", .{})) orelse return;
    const slice = std.mem.span(raw);
    if (slice.len == 0) return;
    _ = addTodozItem(slice.ptr, @intCast(slice.len));
    input_field.send("setStringValue:", .{""});
    refreshTodozList();
}

fn clearCompletedAction(_: Object, _: objc.Sel, _: Object) callconv(cc) void {
    _ = clearCompletedItems();
    refreshTodozList();
}
fn toggleTodozAction(_: Object, _: objc.Sel, sender: Object) callconv(cc) void {
    const btn: AppKit.NSButton = .{ .id = sender };
    _ = toggleTodozItem(@intCast(btn.send("tag", .{})));
    refreshTodozList();
}
fn removeTodozAction(_: Object, _: objc.Sel, sender: Object) callconv(cc) void {
    const btn: AppKit.NSButton = .{ .id = sender };
    _ = removeTodozItem(@intCast(btn.send("tag", .{})));
    refreshTodozList();
}
fn filterChangedAction(_: Object, _: objc.Sel, _: Object) callconv(cc) void {
    refreshTodozList();
}

// ── List refresh ───────────────────────────────────────────────────────

fn currentFilter() i64 {
    return filter_seg.send("selectedSegment", .{});
}

fn todoPassesFilter(t: *const Todoz) bool {
    return switch (currentFilter()) {
        1 => !t.completed,
        2 => t.completed,
        else => true,
    };
}

fn refreshTodozList() void {
    // Remove all arranged subviews
    const subviews: AppKit.NSArrayObj = .{ .id = todo_list_stack.send("arrangedSubviews", .{}) };
    var i: c_ulong = subviews.send("count", .{});
    while (i > 0) {
        i -= 1;
        const view = subviews.send("objectAtIndex:", .{i});
        todo_list_stack.send("removeArrangedSubview:", .{view});
        const v: AppKit.NSView = .{ .id = view };
        v.send("removeFromSuperview", .{});
    }

    var visible: u32 = 0;
    var row_idx: usize = 0;

    for (0..todo_count) |idx| {
        const t = getTodozItem(@intCast(idx)) orelse continue;
        if (!todoPassesFilter(t)) continue;
        todo_list_stack.send("addArrangedSubview:", .{buildTodozRow(t, row_idx).id});
        row_idx += 1;
        visible += 1;
    }

    if (visible == 0) {
        todo_list_stack.send("addArrangedSubview:", .{empty_container.id});
    }

    // Update subtitle
    var buf: [64]u8 = undefined;
    main_window.send("setSubtitle:", .{AppKit.fmtZ("{d} pending \xc2\xb7 {d} done", .{ countPending(), countCompleted() }, &buf)});
}

fn buildTodozRow(t: *const Todoz, idx: usize) AppKit.NSStackView {
    const row = AppKit.NSStackView.static("alloc", .{}).send("initWithFrame:", .{AppKit.NSRect.make(0, 0, 0, 0)});
    row.send("setOrientation:", .{AppKit.NSUserInterfaceLayoutOrientation.horizontal});
    row.send("setSpacing:", .{10});
    row.send("setEdgeInsets:", .{AppKit.NSEdgeInsets{ .top = 10, .left = 16, .bottom = 10, .right = 16 }});

    { // Alternating background
        const rv: AppKit.NSView = .{ .id = row.id };
        rv.send("setWantsLayer:", .{true});
        const layer: AppKit.CALayer = .{ .id = @ptrCast(rv.send("layer", .{}).?) };
        const alpha: f64 = if (idx % 2 == 0) 0.08 else 0.16;
        const color: AppKit.NSColor = .{ .id = AppKit.NSColor.static("colorWithRed:green:blue:alpha:", .{ 0.5, 0.5, 0.5, alpha }) };
        layer.send("setBackgroundColor:", .{color.send("CGColor", .{})});
    }

    const handler = objc.init("TodozActionHandler");

    { // Checkbox
        const sym_name = if (t.completed) "checkmark.circle.fill" else "circle";
        const sym_desc = if (t.completed) "Mark incomplete" else "Mark complete";
        const img = AppKit.NSImage.static("imageWithSystemSymbolName:accessibilityDescription:", .{ sym_name, sym_desc });
        const checkbox: AppKit.NSButton = .{ .id = AppKit.NSButton.static("buttonWithImage:target:action:", .{ img, handler, objc.sel("toggleTodoz:") }) };
        checkbox.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        checkbox.send("setBordered:", .{false});
        checkbox.send("setTag:", .{t.id});
        checkbox.send("setContentTintColor:", .{if (t.completed)
            AppKit.NSColor.static("systemGreenColor", .{})
        else
            AppKit.NSColor.static("secondaryLabelColor", .{})});
        checkbox.send("setSymbolConfiguration:", .{AppKit.NSImageSymbolConfiguration.static("configurationWithPointSize:weight:", .{ 18.0, 0.0 })});
        row.send("addArrangedSubview:", .{checkbox.id});
    }

    { // Title
        var title_buf: [max_title_len + 1]u8 = undefined;
        @memcpy(title_buf[0..t.title_len], t.title[0..t.title_len]);
        title_buf[t.title_len] = 0;

        const label: AppKit.NSTextField = .{ .id = AppKit.NSTextField.static("labelWithString:", .{objc.nsString(@ptrCast(&title_buf))}) };
        label.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        label.send("setFont:", .{AppKit.NSFont.static("systemFontOfSize:", .{13})});
        if (t.completed) {
            label.send("setTextColor:", .{AppKit.NSColor.static("secondaryLabelColor", .{})});
            const str_val = label.send("stringValue", .{});
            const str_len = objc.send(str_val, "length", c_ulong, .{});
            const attr = Foundation.NSMutableAttributedString.static("alloc", .{}).send("initWithString:", .{str_val});
            attr.send("addAttribute:value:range:", .{
                objc.nsString("NSStrikethrough"),                   objc.nsNumberWithInt(1),
                AppKit.NSRange{ .location = 0, .length = str_len },
            });
            label.send("setAttributedStringValue:", .{attr.id});
        }
        label.send("setContentHuggingPriority:forOrientation:", .{ 249, 0 });
        label.send("setContentCompressionResistancePriority:forOrientation:", .{ 749, 0 });
        const cell = objc.send(label.id, "cell", Object, .{});
        objc.send(cell, "setLineBreakMode:", void, .{@as(c_ulong, 4)});
        row.send("addArrangedSubview:", .{label.id});
    }

    { // Delete button
        const img = AppKit.NSImage.static("imageWithSystemSymbolName:accessibilityDescription:", .{ "trash", "Delete" });
        const btn: AppKit.NSButton = .{ .id = AppKit.NSButton.static("buttonWithImage:target:action:", .{ img, handler, objc.sel("removeTodoz:") }) };
        btn.send("setTranslatesAutoresizingMaskIntoConstraints:", .{false});
        btn.send("setBordered:", .{false});
        const red = AppKit.NSColor.static("systemRedColor", .{});
        btn.send("setContentTintColor:", .{red.send("colorWithAlphaComponent:", .{0.7})});
        btn.send("setTag:", .{t.id});
        row.send("addArrangedSubview:", .{btn.id});
    }

    return row;
}
