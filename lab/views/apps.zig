//! View definitions use helpers that produce the same validated, typed AST.
const ui = @import("dsl.zig");
const ref = ui.ref;
const bind = ui.bind;
const str = ui.str;
const describe = ui.describe;
fn stat(comptime name: []const u8, comptime label: []const u8) ui.Node {
    return ui.vstack(8, &.{
        ui.font(ui.text(describe(ref(.uint, name))), .title3),
        ui.font(ui.text(str(label)), .caption),
    });
}
pub const views = [_]ui.View{
    .{ .name = "GeneratedStatePanel", .fields = &.{
        ui.state("count", ui.uint(0), .native),
        ui.state("expanded", ui.boolean(false), .native),
        ui.state("amount", ui.double(1), .native),
        ui.state("note", str("Zig → typed SwiftUI"), .native),
        ui.environment("enabled", .isEnabled, .native),
        ui.environment("scale", .generatedScale, .native),
    }, .body = ui.disabled(ui.vstack(8, &.{
        ui.hstack(8, &.{
            ui.toggle(str("State & environment lab"), bind(.boolean, "expanded"), false),
            .spacer,
            ui.text(str("Count")),
            ui.text(describe(ref(.uint, "count"))),
            ui.button(str("Increment"), ui.increment(bind(.uint, "count"))),
        }),
        ui.when(ref(.boolean, "expanded"), ui.vstack(8, &.{
            ui.textField("String state", bind(.string, "note"), null),
            ui.nativeText(ref(.string, "note")),
            ui.hstack(8, &.{
                ui.text(str("Double state")),
                ui.slider("Double state", bind(.double, "amount"), 0, 10),
                ui.text(describe(ref(.double, "amount"))),
                ui.text(str("Environment scale")),
                ui.text(describe(ref(.double, "scale"))),
            }),
        }), null),
    }), ui.neg(ref(.boolean, "enabled"))) },
    .{ .name = "GeneratedTodoControls", .fields = &.{
        ui.input("title", .string),
        ui.binding("isDone", .boolean),
        ui.input("onDelete", .action),
    }, .body = ui.hstack(12, &.{
        ui.text(str("≡")),
        ui.toggle(ref(.string, "title"), bind(.boolean, "isDone"), true),
        .spacer,
        ui.iconButton("trash", "Delete task", ui.call("onDelete")),
    }) },
    .{ .name = "GeneratedEditorStats", .fields = &.{
        ui.input("words", .uint),
        ui.input("lines", .uint),
        ui.input("scalars", .uint),
        ui.input("bytes", .uint),
        ui.binding("fontSize", .double),
    }, .body = ui.hstack(18, &.{
        stat("words", "WORDS"),
        stat("lines", "LINES"),
        stat("scalars", "SCALARS"),
        stat("bytes", "BYTES"),
        .spacer,
        ui.text(str("Aa")),
        ui.slider("Font size", bind(.double, "fontSize"), 11, 24),
    }) },
    .{ .name = "GeneratedBrowserControls", .fields = &.{
        ui.binding("address", .string),
        ui.input("canGoBack", .boolean),
        ui.input("canGoForward", .boolean),
        ui.input("isLoading", .boolean),
        ui.input("onBack", .action),
        ui.input("onForward", .action),
        ui.input("onReload", .action),
        ui.input("onGo", .action),
        ui.input("onHome", .action),
    }, .body = ui.hstack(10, &.{
        ui.disabled(ui.iconButton("chevron.left", "Back", ui.call("onBack")), ui.neg(ref(.boolean, "canGoBack"))),
        ui.disabled(ui.iconButton("chevron.right", "Forward", ui.call("onForward")), ui.neg(ref(.boolean, "canGoForward"))),
        ui.when(ref(.boolean, "isLoading"), ui.iconButton("xmark", "Stop", ui.call("onReload")), ui.iconButton("arrow.clockwise", "Reload", ui.call("onReload"))),
        ui.textField("Enter an address, e.g. example.com", bind(.string, "address"), ui.call("onGo")),
        ui.button(str("Go"), ui.call("onGo")),
        ui.iconButton("house", "Home", ui.call("onHome")),
    }) },
    .{ .name = "GeneratedKeyedRow", .fields = &.{
        ui.input("item", .item),
        ui.input("tick", .uint),
        ui.input("report", .report),
        ui.state("count", ui.itemID("item"), .native),
    }, .body = ui.onChange(ui.onChange(ui.hstack(8, &.{
        ui.text(ui.itemTitle("item")),
        ui.text(describe(ref(.uint, "count"))),
    }), ref(.uint, "count"), true, ui.report("report", ui.itemID("item"), ref(.uint, "count"))), ref(.uint, "tick"), false, ui.increment(bind(.uint, "count"))) },
    .{ .name = "GeneratedKeyedList", .fields = &.{
        ui.input("items", .items),
        ui.input("tick", .uint),
        ui.input("report", .report),
    }, .body = ui.vstack(8, &.{
        ui.forEach(ref(.items, "items"), "row", ui.component("GeneratedKeyedRow", &.{
            ui.arg("item", ref(.item, "row")),
            ui.arg("tick", ref(.uint, "tick")),
            ui.arg("report", ref(.report, "report")),
        })),
    }) },
    .{ .name = "GeneratedBenchmarkCard", .fields = &.{
        ui.input("title", .string),
        ui.input("count", .uint),
    }, .body = ui.vstack(8, &.{
        ui.text(ref(.string, "title")),
        ui.text(describe(ref(.uint, "count"))),
        ui.hstack(8, &.{ ui.text(str("Typed")), ui.text(str("SwiftUI")) }),
    }) },
};
