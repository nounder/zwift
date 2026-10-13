//! A closed, typed SwiftUI AST. No raw Swift snippets are accepted.
const std = @import("std");
pub const Value = enum { boolean, uint, double, string, items, item, action, report };
pub const Storage = enum { input, state, binding, environment };
pub const ExprNode = union(enum) {
    ref: []const u8,
    boolean: bool,
    uint: u64,
    double: f64,
    string: []const u8,
    not: *const ExprNode,
    describe: *const ExprNode,
    item_title: []const u8,
    item_id: []const u8,
};
pub fn Expr(comptime kind: Value) type {
    return struct {
        pub const value = kind;
        node: ExprNode,
    };
}
pub fn ref(comptime kind: Value, name: []const u8) Expr(kind) {
    return .{ .node = .{ .ref = name } };
}
pub fn str(value: []const u8) Expr(.string) {
    return .{ .node = .{ .string = value } };
}
pub fn describe(comptime value: anytype) Expr(.string) {
    return .{ .node = .{ .describe = &value.node } };
}
pub fn neg(comptime value: Expr(.boolean)) Expr(.boolean) {
    return .{ .node = .{ .not = &value.node } };
}
pub fn Binding(comptime kind: Value) type {
    return struct {
        pub const value = kind;
        name: []const u8,
    };
}
pub fn bind(comptime kind: Value, name: []const u8) Binding(kind) {
    return .{ .name = name };
}
pub const EnvironmentKey = enum { isEnabled, generatedScale };
pub const Font = enum { caption, headline, title3 };
pub const Field = struct {
    name: []const u8,
    value: Value,
    storage: Storage = .input,
    initial: ?ExprNode = null,
    native: bool = false,
    key: ?EnvironmentKey = null,
};
pub const Action = union(enum) {
    call: []const u8,
    increment: Binding(.uint),
    toggle: Binding(.boolean),
    report: struct { callback: []const u8, id: Expr(.uint), value: Expr(.uint) },
};
pub const Argument = struct { name: []const u8, source: union(enum) { value: ExprNode, binding: []const u8 } };
pub const Node = union(enum) {
    text: Expr(.string),
    native_text: Expr(.string),
    spacer,
    divider,
    hstack: Stack,
    vstack: Stack,
    button: struct { title: Expr(.string), action: Action },
    icon_button: struct { symbol: []const u8, label: []const u8, action: Action },
    toggle: struct { title: Expr(.string), value: Binding(.boolean), checkbox: bool = false },
    text_field: struct { title: []const u8, value: Binding(.string), submit: ?Action = null },
    slider: struct { label: []const u8, value: Binding(.double), min: f64, max: f64 },
    branch: struct { condition: Expr(.boolean), yes: *const Node, no: ?*const Node = null },
    for_each: struct { items: Expr(.items), name: []const u8, body: *const Node },
    component: struct { name: []const u8, args: []const Argument },
    styled: struct { content: *const Node, padding: ?u8 = null, font: ?Font = null, disabled: ?Expr(.boolean) = null, border: bool = false },
    on_change: struct { content: *const Node, value: ExprNode, initial: bool = false, action: Action },
    pub const Stack = struct { spacing: u8 = 8, children: []const Node };
};
pub const View = struct { name: []const u8, fields: []const Field, body: Node };
pub const Error = error{ InvalidIdentifier, DuplicateName, UnknownField, TypeMismatch, ReadOnlyBinding, UnsupportedState, InvalidEnvironment, InvalidComponent, MissingArgument, UnexpectedArgument, InvalidRange, InvalidString, ComponentCycle };
// One small diagnostic travels through the existing validator; no second validation pass.
pub const Diagnostic = struct {
    view: []const u8 = "schema",
    subject: []const u8 = "body",
    component: ?[]const u8 = null,
    expected: ?Value = null,
    actual: ?Value = null,
    writable: bool = false,

    pub fn message(comptime d: Diagnostic, comptime err: Error) []const u8 {
        const location = d.view ++ "." ++ (if (d.component) |c| c ++ "." else "") ++ d.subject ++ ": ";
        const expected = if (d.expected) |v| "expected " ++ (if (d.writable) "writable " else "") ++ swiftType(v) else "type mismatch";
        const found = if (d.actual) |v| "; found " ++ swiftType(v) else "";
        return location ++ switch (err) {
            error.TypeMismatch => expected ++ found,
            error.ReadOnlyBinding => if (d.writable) expected ++ "; field is read-only" else "state initializer may reference constructor inputs only",
            error.UnknownField => "unknown field",
            error.InvalidEnvironment => "invalid environment key/type" ++ (if (d.expected != null) "; " ++ expected ++ found else ""),
            error.InvalidIdentifier => "invalid or reserved Swift identifier",
            error.DuplicateName => "duplicate name or argument",
            error.MissingArgument => "missing component argument",
            error.UnexpectedArgument => "unexpected component argument",
            error.InvalidComponent => "unknown component or unsupported nested ForEach",
            error.ComponentCycle => "recursive component or view nesting exceeds 64 levels",
            error.UnsupportedState => "unsupported storage type or initializer",
            error.InvalidRange => "expected finite numbers and an increasing slider range",
            error.InvalidString => "expected valid UTF-8",
        };
    }
};
fn expressionName(e: ExprNode) ?[]const u8 {
    return switch (e) {
        .ref, .item_id, .item_title => |name| name,
        .not, .describe => |inner| expressionName(inner.*),
        else => null,
    };
}
fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn identifier(name: []const u8) Error!void {
    if (name.len == 0 or !std.ascii.isAlphabetic(name[0])) return error.InvalidIdentifier;
    for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return error.InvalidIdentifier;
    for ([_][]const u8{ "self", "Self", "body", "init", "deinit", "var", "let", "class", "struct", "enum", "protocol", "extension", "func", "return", "if", "else", "for", "in", "switch", "case", "default", "true", "false", "nil", "some", "any", "Type", "actor", "async", "await", "throws", "throw", "try", "do", "catch", "while", "repeat", "break", "continue", "guard", "defer", "where", "associatedtype", "typealias", "import", "inout", "operator", "subscript", "static", "private", "public", "internal", "fileprivate", "open", "super", "as", "is", "fallthrough", "rethrows", "switch", "return", "View", "Text", "String", "Double", "Bool", "UInt64", "State", "Binding", "Environment", "GeneratedItem", "GeneratedScaleKey", "EnvironmentValues" }) |word| if (same(word, name)) return error.InvalidIdentifier;
}
fn field(view: View, name: []const u8) Error!Field {
    for (view.fields) |f| if (same(f.name, name)) return f;
    return error.UnknownField;
}
fn lookup(view: View, local: ?[]const u8, name: []const u8) Error!Value {
    if (local) |l| if (same(l, name)) return .item;
    return (try field(view, name)).value;
}
fn infer(view: View, local: ?[]const u8, expr: ExprNode) Error!Value {
    return switch (expr) {
        .ref => |name| try lookup(view, local, name),
        .boolean => .boolean,
        .uint => .uint,
        .double => |d| if (std.math.isFinite(d)) .double else error.InvalidRange,
        .string => |s| if (std.unicode.utf8ValidateSlice(s)) .string else error.InvalidString,
        .not => |e| if (try infer(view, local, e.*) == .boolean) .boolean else error.TypeMismatch,
        .describe => |e| switch (try infer(view, local, e.*)) {
            .boolean, .uint, .double, .string => .string,
            else => error.TypeMismatch,
        },
        .item_title, .item_id => |name| if (try lookup(view, local, name) == .item) (if (expr == .item_title) .string else .uint) else error.TypeMismatch,
    };
}
fn expect(view: View, local: ?[]const u8, expr: anytype, d: *Diagnostic) Error!void {
    d.* = .{ .view = view.name, .subject = expressionName(expr.node) orelse "expression", .expected = @TypeOf(expr).value };
    d.actual = try infer(view, local, expr.node);
    if (d.actual.? != @TypeOf(expr).value) return error.TypeMismatch;
}
fn writable(view: View, name: []const u8, kind: Value, d: *Diagnostic) Error!void {
    d.* = .{ .view = view.name, .subject = name, .expected = kind, .writable = true };
    const f = try field(view, name);
    d.actual = f.value;
    if (f.value != kind) return error.TypeMismatch;
    if (f.storage != .state and f.storage != .binding) return error.ReadOnlyBinding;
}
fn action(view: View, local: ?[]const u8, a: Action, d: *Diagnostic) Error!void {
    switch (a) {
        .call => |name| try expect(view, local, ref(.action, name), d),
        .increment => |b| try writable(view, b.name, .uint, d),
        .toggle => |b| try writable(view, b.name, .boolean, d),
        .report => |r| {
            try expect(view, local, ref(.report, r.callback), d);
            try expect(view, local, r.id, d);
            try expect(view, local, r.value, d);
        },
    }
}
fn component(views: []const View, name: []const u8) Error!View {
    for (views) |v| if (same(v.name, name)) return v;
    return error.InvalidComponent;
}
fn node(views: []const View, view: View, local: ?[]const u8, n: Node, depth: usize, d: *Diagnostic) Error!void {
    d.* = .{ .view = view.name, .subject = @tagName(n) };
    if (depth > 64) return error.ComponentCycle;
    switch (n) {
        .text, .native_text => |e| try expect(view, local, e, d),
        .spacer, .divider => {},
        .hstack, .vstack => |s| for (s.children) |child| try node(views, view, local, child, depth + 1, d),
        .button => |b| {
            try expect(view, local, b.title, d);
            try action(view, local, b.action, d);
        },
        .icon_button => |b| {
            if (!std.unicode.utf8ValidateSlice(b.symbol) or !std.unicode.utf8ValidateSlice(b.label)) return error.InvalidString;
            try action(view, local, b.action, d);
        },
        .toggle => |t| {
            try expect(view, local, t.title, d);
            try writable(view, t.value.name, .boolean, d);
        },
        .text_field => |t| {
            if (!std.unicode.utf8ValidateSlice(t.title)) return error.InvalidString;
            try writable(view, t.value.name, .string, d);
            if (t.submit) |a| try action(view, local, a, d);
        },
        .slider => |s| {
            if (!std.unicode.utf8ValidateSlice(s.label)) return error.InvalidString;
            if (!std.math.isFinite(s.min) or !std.math.isFinite(s.max) or s.min >= s.max) return error.InvalidRange;
            try writable(view, s.value.name, .double, d);
        },
        .branch => |b| {
            try expect(view, local, b.condition, d);
            try node(views, view, local, b.yes.*, depth + 1, d);
            if (b.no) |no| try node(views, view, local, no.*, depth + 1, d);
        },
        .for_each => |f| {
            d.subject = f.name;
            try identifier(f.name);
            if (local != null) return error.InvalidComponent;
            for (view.fields) |v| if (same(v.name, f.name)) return error.DuplicateName;
            try expect(view, local, f.items, d);
            try node(views, view, f.name, f.body.*, depth + 1, d);
        },
        .component => |c| {
            d.subject = c.name;
            const child = try component(views, c.name);
            for (child.fields) |f| {
                if (f.storage != .input and f.storage != .binding) continue;
                d.* = .{ .view = view.name, .component = c.name, .subject = f.name, .expected = f.value, .writable = f.storage == .binding };
                var count: usize = 0;
                for (c.args) |arg| if (same(arg.name, f.name)) {
                    count += 1;
                    switch (arg.source) {
                        .binding => |name| {
                            if (f.storage != .binding) return error.TypeMismatch;
                            try writable(view, name, f.value, d);
                        },
                        .value => |e| {
                            d.actual = try infer(view, local, e);
                            if (f.storage == .binding or d.actual.? != f.value) return error.TypeMismatch;
                        },
                    }
                };
                if (count == 0) return error.MissingArgument;
                if (count != 1) return error.DuplicateName;
            }
            for (c.args) |arg| {
                d.* = .{ .view = view.name, .component = c.name, .subject = arg.name };
                const f = field(child, arg.name) catch return error.UnexpectedArgument;
                if (f.storage != .input and f.storage != .binding) return error.UnexpectedArgument;
            }
            try node(views, child, null, child.body, depth + 1, d);
        },
        .styled => |s| {
            try node(views, view, local, s.content.*, depth + 1, d);
            if (s.disabled) |e| try expect(view, local, e, d);
        },
        .on_change => |o| {
            switch (try infer(view, local, o.value)) {
                .boolean, .uint, .double, .string => {},
                else => return error.TypeMismatch,
            }
            try action(view, local, o.action, d);
            try node(views, view, local, o.content.*, depth + 1, d);
        },
    }
}
// Initializers run before SwiftUI installs storage; only constructor inputs exist here.
fn initialInput(view: View, e: ExprNode) Error!void {
    switch (e) {
        .ref, .item_title, .item_id => |name| if ((try field(view, name)).storage != .input) return error.ReadOnlyBinding,
        .not, .describe => |child| try initialInput(view, child.*),
        else => {},
    }
}
pub fn validate(views: []const View) Error!void {
    var diagnostic: Diagnostic = .{};
    return validateDetailed(views, &diagnostic);
}
pub fn validateDetailed(views: []const View, d: *Diagnostic) Error!void {
    for (views, 0..) |v, i| {
        d.* = .{ .view = v.name, .subject = "declaration" };
        try identifier(v.name);
        for (views[0..i]) |before| if (same(before.name, v.name)) return error.DuplicateName;
        for (v.fields, 0..) |f, j| {
            d.* = .{ .view = v.name, .subject = f.name };
            try identifier(f.name);
            for (v.fields[0..j]) |before| if (same(before.name, f.name)) return error.DuplicateName;
            if (f.storage != .state and f.initial != null) return error.UnsupportedState;
            if (f.storage != .environment and f.key != null) return error.InvalidEnvironment;
            if (f.native and f.storage != .state and f.storage != .environment) return error.UnsupportedState;
            switch (f.storage) {
                .state => {
                    switch (f.value) {
                        .boolean, .uint, .double, .string => {},
                        else => return error.UnsupportedState,
                    }
                    d.expected = f.value;
                    d.actual = try infer(v, null, f.initial orelse return error.UnsupportedState);
                    if (d.actual.? != f.value) return error.TypeMismatch;
                    try initialInput(v, f.initial.?);
                },
                .environment => {
                    const key = f.key orelse return error.InvalidEnvironment;
                    const kind: Value = if (key == .isEnabled) .boolean else .double;
                    d.expected = kind;
                    d.actual = f.value;
                    if (f.value != kind) return error.InvalidEnvironment;
                },
                .binding => switch (f.value) {
                    .boolean, .uint, .double, .string => {},
                    else => return error.UnsupportedState,
                },
                .input => {},
            }
        }
        try node(views, v, null, v.body, 0, d);
    }
}

fn swiftType(comptime kind: Value) []const u8 {
    return switch (kind) {
        .boolean => "Bool",
        .uint => "UInt64",
        .double => "Double",
        .string => "String",
        .items => "[GeneratedItem]",
        .item => "GeneratedItem",
        .action => "() -> Void",
        .report => "(UInt64, UInt64) -> Void",
    };
}
fn quote(comptime value: []const u8) []const u8 {
    var result: []const u8 = "\"";
    for (value) |c| result = result ++ switch (c) {
        '"' => "\\\"",
        '\\' => "\\\\",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t",
        else => if (c < 32) std.fmt.comptimePrint("\\u{{{x}}}", .{c}) else &[_]u8{c},
    };
    return result ++ "\"";
}
fn emitExpr(comptime e: ExprNode) []const u8 {
    return switch (e) {
        .ref => |name| name,
        .boolean => |b| if (b) "true" else "false",
        .uint => |n| std.fmt.comptimePrint("{d}", .{n}),
        .double => |d| "Double(" ++ std.fmt.comptimePrint("{d}", .{d}) ++ ")",
        .string => |s| quote(s),
        .not => |v| "!(" ++ emitExpr(v.*) ++ ")",
        .describe => |v| "String(describing: " ++ emitExpr(v.*) ++ ")",
        .item_title => |name| name ++ ".title",
        .item_id => |name| name ++ ".id",
    };
}
fn emitAction(comptime a: Action) []const u8 {
    return switch (a) {
        .call => |name| name ++ "()",
        .increment => |b| b.name ++ " &+= 1",
        .toggle => |b| b.name ++ ".toggle()",
        .report => |r| r.callback ++ "(" ++ emitExpr(r.id.node) ++ ", " ++ emitExpr(r.value.node) ++ ")",
    };
}
fn emitNode(comptime views: []const View, comptime n: Node) []const u8 {
    return switch (n) {
        .text => |e| "Text(verbatim: " ++ emitExpr(e.node) ++ ")",
        .native_text => |e| "nativeTextString(" ++ emitExpr(e.node) ++ ")",
        .spacer => "Spacer()",
        .divider => "Divider()",
        .hstack, .vstack => |s| blk: {
            var result: []const u8 = if (n == .hstack) "HStack" else "VStack";
            result = result ++ std.fmt.comptimePrint("(spacing: {d}) {{\n", .{s.spacing});
            for (s.children) |child| result = result ++ emitNode(views, child) ++ "\n";
            break :blk result ++ "}";
        },
        .button => |b| "Button(action: { " ++ emitAction(b.action) ++ " }) { Text(verbatim: " ++ emitExpr(b.title.node) ++ ") }",
        .icon_button => |b| "Button(action: { " ++ emitAction(b.action) ++ " }) { Image(systemName: " ++ quote(b.symbol) ++ ") }.accessibilityLabel(" ++ quote(b.label) ++ ").buttonStyle(.borderless)",
        .toggle => |t| "Toggle(isOn: $" ++ t.value.name ++ ") { Text(verbatim: " ++ emitExpr(t.title.node) ++ ") }" ++ (if (t.checkbox) ".toggleStyle(.checkbox)" else ".toggleStyle(.switch)"),
        .text_field => |t| "TextField(" ++ quote(t.title) ++ ", text: $" ++ t.value.name ++ ").textFieldStyle(.roundedBorder)" ++ (if (t.submit) |a| ".onSubmit { " ++ emitAction(a) ++ " }" else ""),
        .slider => |s| "Slider(value: $" ++ s.value.name ++ ", in: " ++ std.fmt.comptimePrint("{d}...{d}", .{ s.min, s.max }) ++ ").accessibilityLabel(" ++ quote(s.label) ++ ")",
        .branch => |b| "if " ++ emitExpr(b.condition.node) ++ " {\n" ++ emitNode(views, b.yes.*) ++ "\n}" ++ (if (b.no) |no| " else {\n" ++ emitNode(views, no.*) ++ "\n}" else ""),
        .for_each => |f| "ForEach(" ++ emitExpr(f.items.node) ++ ") { " ++ f.name ++ " in\n" ++ emitNode(views, f.body.*) ++ "\n}",
        .component => |c| blk: {
            var result: []const u8 = c.name ++ "(";
            var count: usize = 0;
            const child = component(views, c.name) catch unreachable;
            for (child.fields) |f| {
                if (f.storage != .input and f.storage != .binding) continue;
                for (c.args) |arg| if (same(arg.name, f.name)) {
                    if (count > 0) result = result ++ ", ";
                    count += 1;
                    result = result ++ arg.name ++ ": " ++ switch (arg.source) {
                        .value => |e| emitExpr(e),
                        .binding => |name| "$" ++ name,
                    };
                };
            }
            break :blk result ++ ")";
        },
        .styled => |s| blk: {
            var result: []const u8 = "Group {\n" ++ emitNode(views, s.content.*) ++ "\n}";
            if (s.padding) |p| result = result ++ std.fmt.comptimePrint(".padding({d})", .{p});
            if (s.font) |f| result = result ++ ".font(." ++ @tagName(f) ++ ")";
            if (s.disabled) |d| result = result ++ ".disabled(" ++ emitExpr(d.node) ++ ")";
            if (s.border) result = result ++ ".buttonStyle(.bordered)";
            break :blk result;
        },
        .on_change => |o| "Group {\n" ++ emitNode(views, o.content.*) ++ "\n}" ++ ".onChange(of: " ++ emitExpr(o.value) ++ ", initial: " ++ (if (o.initial) "true" else "false") ++ ") { _, _ in " ++ emitAction(o.action) ++ " }",
    };
}
fn factory(comptime f: Field) []const u8 {
    if (f.storage == .environment) return (if (f.native) (if (f.value == .boolean) "nativeEnvironment" else "nativeEnvironmentDouble") else "Environment") ++ "(\\." ++ @tagName(f.key.?) ++ ")";
    const init_expr = emitExpr(f.initial.?);
    if (!f.native) return "State(wrappedValue: " ++ init_expr ++ ")";
    const name = switch (f.value) {
        .boolean => "nativeStateBool",
        .uint => "nativeState",
        .double => "nativeStateDouble",
        .string => "nativeStateString",
        else => unreachable,
    };
    return name ++ "(" ++ init_expr ++ ")";
}
pub fn emit(comptime views: []const View) []const u8 {
    comptime {
        @setEvalBranchQuota(1000000);
        var diagnostic: Diagnostic = .{};
        validateDetailed(views, &diagnostic) catch |e| @compileError(diagnostic.message(e));
        var result: []const u8 =
            \\// Generated from typed Zig nodes. Do not edit.
            \\import SwiftUI
            \\struct GeneratedItem: Identifiable { let id: UInt64; let title: String }
            \\private struct GeneratedScaleKey: EnvironmentKey { static let defaultValue: Double = 1 }
            \\extension EnvironmentValues {
            \\    var generatedScale: Double { get { self[GeneratedScaleKey.self] } set { self[GeneratedScaleKey.self] = newValue } }
            \\}
            \\
        ;
        for (views) |v| {
            result = result ++ "// Zig view: " ++ v.name ++ "\nstruct " ++ v.name ++ ": View {\n";
            for (v.fields) |f| result = result ++ "// Zig field: " ++ v.name ++ "." ++ f.name ++ " (" ++ @tagName(f.storage) ++ ")\n" ++ switch (f.storage) {
                .input => "let ",
                .state => "@State private var ",
                .binding => "@Binding var ",
                .environment => "@Environment private var ",
            } ++ f.name ++ ": " ++ swiftType(f.value) ++ "\n";
            result = result ++ "init(";
            var count: usize = 0;
            for (v.fields) |f| {
                if (f.storage != .input and f.storage != .binding) continue;
                if (count > 0) result = result ++ ", ";
                count += 1;
                result = result ++ f.name ++ ": " ++ (if (f.storage == .binding) "Binding<" ++ swiftType(f.value) ++ ">" else (if (f.value == .action or f.value == .report) "@escaping " else "") ++ swiftType(f.value));
            }
            result = result ++ ") {\n";
            for (v.fields) |f| result = result ++ switch (f.storage) {
                .input => "self." ++ f.name ++ " = " ++ f.name ++ "\n",
                .binding => "self._" ++ f.name ++ " = " ++ f.name ++ "\n",
                .state, .environment => "self._" ++ f.name ++ " = " ++ factory(f) ++ "\n",
            };
            result = result ++ "}\nvar body: some View {\n" ++ emitNode(views, v.body) ++ "\n}\n}\n";
        }
        return result;
    }
}
