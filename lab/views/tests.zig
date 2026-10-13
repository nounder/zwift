const std = @import("std");
const ui = @import("schema.zig");
const t = std.testing;
fn validate(fields: []const ui.Field, body: ui.Node) ui.Error!void {
    return ui.validate(&.{.{ .name = "Example", .fields = fields, .body = body }});
}
test "typed programs reject unknown references, false type annotations and read-only bindings" {
    try t.expectError(error.UnknownField, validate(&.{}, .{ .text = ui.ref(.string, "missing") }));
    try t.expectError(error.TypeMismatch, validate(&.{.{ .name = "count", .value = .uint }}, .{ .text = ui.ref(.string, "count") }));
    try t.expectError(error.ReadOnlyBinding, validate(&.{.{ .name = "flag", .value = .boolean }}, .{ .toggle = .{ .title = ui.str("Toggle"), .value = ui.bind(.boolean, "flag") } }));
    try t.expectError(error.TypeMismatch, validate(&.{.{ .name = "count", .value = .uint, .storage = .state, .initial = .{ .uint = 0 } }}, .{ .toggle = .{ .title = ui.str("Toggle"), .value = ui.bind(.boolean, "count") } }));
    try t.expectError(error.TypeMismatch, validate(&.{.{ .name = "callback", .value = .string }}, .{ .button = .{ .title = ui.str("Call"), .action = .{ .call = "callback" } } }));
}
test "storage initialization and environment key types are checked before Swift compilation" {
    try t.expectError(error.InvalidEnvironment, validate(&.{.{ .name = "scale", .value = .boolean, .storage = .environment, .key = .generatedScale }}, .spacer));
    try t.expectError(error.UnsupportedState, validate(&.{.{ .name = "value", .value = .items, .storage = .state, .initial = .{ .uint = 0 } }}, .spacer));
    try t.expectError(error.ReadOnlyBinding, validate(&.{.{ .name = "value", .value = .uint, .storage = .state, .initial = .{ .ref = "value" } }}, .spacer));
    try t.expectError(error.InvalidIdentifier, validate(&.{.{ .name = "_count", .value = .uint }}, .spacer));
    try t.expectError(error.InvalidIdentifier, validate(&.{.{ .name = "await", .value = .uint }}, .spacer));
    try t.expectError(error.InvalidIdentifier, validate(&.{.{ .name = "name); fatalError()", .value = .uint }}, .spacer));
    try t.expectError(error.InvalidString, validate(&.{}, .{ .text = ui.str("\xff") }));
}
test "component arguments are complete, unique and emitted in declaration order" {
    const child: ui.View = comptime .{ .name = "Child", .fields = &.{ .{ .name = "title", .value = .string }, .{ .name = "number", .value = .uint } }, .body = .spacer };
    try t.expectError(error.MissingArgument, ui.validate(&.{ child, .{ .name = "Parent", .fields = &.{}, .body = .{ .component = .{ .name = "Child", .args = &.{} } } } }));
    const source = comptime ui.emit(&.{ child, .{ .name = "Parent", .fields = &.{}, .body = .{ .component = .{ .name = "Child", .args = &.{ .{ .name = "number", .source = .{ .value = .{ .uint = 7 } } }, .{ .name = "title", .source = .{ .value = .{ .string = "OK" } } } } } } } });
    try t.expect(std.mem.indexOf(u8, source, "Child(title: \"OK\", number: 7)") != null);
    try t.expectError(error.ComponentCycle, ui.validate(&.{.{ .name = "Recursive", .fields = &.{}, .body = .{ .component = .{ .name = "Recursive", .args = &.{} } } }}));
}
test "source literal escaping preserves Unicode and cannot introduce Swift interpolation" {
    const source = comptime ui.emit(&.{.{ .name = "Escaped", .fields = &.{}, .body = .{ .text = ui.str("\"\\(danger())\n\t\x01👋") } }});
    try t.expect(std.mem.indexOf(u8, source, "Text(verbatim: \"\\\"\\\\(danger())\\n\\t\\u{1}👋\")") != null);
    try ui.validate(&@import("apps.zig").views);
}

test "helpers still reject invalid bindings with actionable component and field diagnostics" {
    const dsl = @import("dsl.zig");
    const message = comptime blk: {
        var d: ui.Diagnostic = .{};
        ui.validateDetailed(&.{.{ .name = "GeneratedTodoControls", .fields = &.{dsl.input("isDone", .boolean)}, .body = dsl.toggle(dsl.str("Done"), dsl.bind(.boolean, "isDone"), true) }}, &d) catch |err| break :blk d.message(err);
        @compileError("read-only binding must fail validation");
    };
    try t.expectEqualStrings("GeneratedTodoControls.isDone: expected writable Bool; field is read-only", message);
    const mismatch = comptime blk: {
        var d: ui.Diagnostic = .{};
        ui.validateDetailed(&.{.{ .name = "Counter", .fields = &.{dsl.state("count", dsl.uint(0), .native)}, .body = dsl.toggle(dsl.str("Wrong type"), dsl.bind(.boolean, "count"), false) }}, &d) catch |err| break :blk d.message(err);
        @compileError("wrongly typed binding must fail validation");
    };
    try t.expectEqualStrings("Counter.count: expected writable Bool; found UInt64", mismatch);
}
test "nested components and constructor arguments retain the failing scope" {
    const child: ui.View = comptime .{ .name = "Child", .fields = &.{.{ .name = "title", .value = .string }}, .body = .{ .text = ui.ref(.string, "missing") } };
    const nested = comptime blk: {
        var d: ui.Diagnostic = .{};
        ui.validateDetailed(&.{ .{ .name = "Parent", .fields = &.{}, .body = .{ .component = .{ .name = "Child", .args = &.{.{ .name = "title", .source = .{ .value = .{ .string = "OK" } } }} } } }, child }, &d) catch |err| break :blk d.message(err);
        @compileError("unknown nested field must fail validation");
    };
    try t.expectEqualStrings("Child.missing: unknown field", nested);
    const missing = comptime blk: {
        var d: ui.Diagnostic = .{};
        ui.validateDetailed(&.{ .{ .name = "Parent", .fields = &.{}, .body = .{ .component = .{ .name = "Child", .args = &.{} } } }, child }, &d) catch |err| break :blk d.message(err);
        @compileError("missing argument must fail validation");
    };
    try t.expectEqualStrings("Parent.Child.title: missing component argument", missing);
}
