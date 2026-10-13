//! Comptime convenience functions for the existing typed AST; no runtime layer.
const schema = @import("schema.zig");
pub const View = schema.View;
pub const Node = schema.Node;
pub const Field = schema.Field;
pub const Value = schema.Value;
pub const Expr = schema.Expr;
pub const Binding = schema.Binding;
pub const Action = schema.Action;
pub const ref = schema.ref;
pub const bind = schema.bind;
pub const str = schema.str;
pub const describe = schema.describe;
pub const neg = schema.neg;
pub const Factory = enum { swift, native };

pub fn boolean(value: bool) Expr(.boolean) {
    return .{ .node = .{ .boolean = value } };
}
pub fn uint(value: u64) Expr(.uint) {
    return .{ .node = .{ .uint = value } };
}
pub fn double(value: f64) Expr(.double) {
    return .{ .node = .{ .double = value } };
}
pub fn itemID(name: []const u8) Expr(.uint) {
    return .{ .node = .{ .item_id = name } };
}
pub fn itemTitle(name: []const u8) Expr(.string) {
    return .{ .node = .{ .item_title = name } };
}
pub fn input(name: []const u8, kind: Value) Field {
    return .{ .name = name, .value = kind };
}
pub fn binding(name: []const u8, kind: Value) Field {
    return .{ .name = name, .value = kind, .storage = .binding };
}
pub fn state(name: []const u8, initial: anytype, factory: Factory) Field {
    return .{ .name = name, .value = @TypeOf(initial).value, .storage = .state, .initial = initial.node, .native = factory == .native };
}
pub fn environment(name: []const u8, key: schema.EnvironmentKey, factory: Factory) Field {
    return .{ .name = name, .value = if (key == .isEnabled) .boolean else .double, .storage = .environment, .key = key, .native = factory == .native };
}
pub fn text(value: Expr(.string)) Node {
    return .{ .text = value };
}
pub fn nativeText(value: Expr(.string)) Node {
    return .{ .native_text = value };
}
pub fn hstack(spacing: u8, children: []const Node) Node {
    return .{ .hstack = .{ .spacing = spacing, .children = children } };
}
pub fn vstack(spacing: u8, children: []const Node) Node {
    return .{ .vstack = .{ .spacing = spacing, .children = children } };
}
pub fn button(title: Expr(.string), action: Action) Node {
    return .{ .button = .{ .title = title, .action = action } };
}
pub fn iconButton(symbol: []const u8, label: []const u8, action: Action) Node {
    return .{ .icon_button = .{ .symbol = symbol, .label = label, .action = action } };
}
pub fn toggle(title: Expr(.string), value: Binding(.boolean), checkbox: bool) Node {
    return .{ .toggle = .{ .title = title, .value = value, .checkbox = checkbox } };
}
pub fn textField(title: []const u8, value: Binding(.string), submit: ?Action) Node {
    return .{ .text_field = .{ .title = title, .value = value, .submit = submit } };
}
pub fn slider(label: []const u8, value: Binding(.double), min: f64, max: f64) Node {
    return .{ .slider = .{ .label = label, .value = value, .min = min, .max = max } };
}
pub fn font(comptime content: Node, value: schema.Font) Node {
    return .{ .styled = .{ .content = &content, .font = value } };
}
pub fn disabled(comptime content: Node, condition: Expr(.boolean)) Node {
    return .{ .styled = .{ .content = &content, .disabled = condition } };
}
pub fn when(condition: Expr(.boolean), comptime yes: Node, comptime no: ?Node) Node {
    return .{ .branch = .{ .condition = condition, .yes = &yes, .no = if (no) |*n| n else null } };
}
pub fn forEach(items: Expr(.items), name: []const u8, comptime body: Node) Node {
    return .{ .for_each = .{ .items = items, .name = name, .body = &body } };
}
pub fn component(name: []const u8, args: []const schema.Argument) Node {
    return .{ .component = .{ .name = name, .args = args } };
}
pub fn arg(name: []const u8, value: anytype) schema.Argument {
    return .{ .name = name, .source = .{ .value = value.node } };
}
pub fn onChange(comptime content: Node, value: anytype, initial: bool, action: Action) Node {
    return .{ .on_change = .{ .content = &content, .value = value.node, .initial = initial, .action = action } };
}
pub fn call(name: []const u8) Action {
    return .{ .call = name };
}
pub fn increment(value: Binding(.uint)) Action {
    return .{ .increment = value };
}
pub fn report(callback: []const u8, id: Expr(.uint), value: Expr(.uint)) Action {
    return .{ .report = .{ .callback = callback, .id = id, .value = value } };
}
