import SwiftUI
import Observation
import UniformTypeIdentifiers

struct TodoDrag: Codable, Transferable {
    let session: UUID
    let id: UInt64
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "dev.zwift.todo-item"))
    }
}

struct TodoSnapshot: Identifiable, Equatable {
    let id: UInt64
    let title: String
    let done: Bool
}

private func todoDidChange(_ context: UnsafeMutableRawPointer?, _ mask: UInt64) {
    guard let context else { return }
    let model = Unmanaged<TodoModel>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        model.refresh(mask: mask)
    }
}

@MainActor @Observable final class TodoModel {
    @ObservationIgnored let core = CoreHandle()
    @ObservationIgnored let session = UUID()
    var rows: [TodoSnapshot] = []
    var revision: UInt64 = 0
    init(seed: Bool = true) {
        zw_observe(core.raw, todoDidChange, Unmanaged.passUnretained(self).toOpaque())
        if seed {
            add("Explore the native Swift ABI")
            add("Drag this task above the first one")
            add("Try a different appearance")
        }
    }
    // Unregister before the unretained callback context can become invalid.
    isolated deinit { zw_observe(core.raw, nil, nil) }
    func refresh(mask: UInt64) {
        if mask & 1 != 0 {
            rows = (0..<zw_todo_count(core.raw)).map { index in
                let info = zw_todo_at(core.raw, index, nil, 0)
                return TodoSnapshot(id: info.id, title: core.read { zw_todo_at(core.raw, index, $0, $1).title_bytes }, done: info.done != 0)
            }
        }
        revision = zw_revision(core.raw)
    }
    @discardableResult func add(_ title: String) -> Bool { withUTF8(title) { zw_todo_add(core.raw, $0, $1) != 0 } }
    func toggle(_ id: UInt64) { _ = zw_todo_toggle(core.raw, id) }
    func remove(_ id: UInt64) { _ = zw_todo_remove(core.raw, id) }
    @discardableResult func move(_ id: UInt64, before: UInt64) -> Bool { zw_todo_move(core.raw, id, before) != 0 }
}

struct TodoRoot: View {
    @State private var model = TodoModel()
    var body: some View { TodoContent().environment(model) }
}

private struct TodoContent: View {
    @Environment(TodoModel.self) private var model
    @Environment(LabSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @State private var draft = ""
    @State private var filter = 0
    @State private var error: String?
    private var env: LabEnvironment { .init(dark: scheme == .dark, compact: settings.compact, allowHTTP: settings.allowHTTP) }
    private var visible: [TodoSnapshot] { model.rows.filter { filter == 0 || (filter == 1 ? !$0.done : $0.done) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("What would you like to do?", text: $draft).textFieldStyle(.roundedBorder).onSubmit(add)
                    .accessibilityIdentifier("todo-input")
                Button("Add task", systemImage: "plus", action: add).buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
            HStack {
                Text("\(model.rows.filter { !$0.done }.count) remaining").font(.subheadline.weight(.medium))
                Spacer()
                Picker("Filter", selection: $filter) { Text("All").tag(0); Text("Active").tag(1); Text("Done").tag(2) }
                    .pickerStyle(.segmented).frame(width: 220)
            }.padding(.horizontal, 24).padding(.bottom, 16)
            ScrollView {
                LazyVStack(spacing: settings.compact ? 4 : 10) {
                    ForEach(visible) { row in
                        TodoRow(row: row)
                            .draggable(TodoDrag(session: model.session, id: row.id))
                            .dropDestination(for: TodoDrag.self) { items, _ in
                                guard let item = items.first, item.session == model.session else { return false }
                                return withAnimation { model.move(item.id, before: row.id) }
                            }
                    }
                    if visible.isEmpty { ContentUnavailableView("A clear list", systemImage: "checkmark.seal", description: Text("Add a task or change the filter.")) }
                    Text("Drop here to move to the end").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(18).contentShape(Rectangle())
                        .dropDestination(for: TodoDrag.self) { items, _ in
                            guard let item = items.first, item.session == model.session else { return false }
                            return withAnimation { model.move(item.id, before: 0) }
                        }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption).padding(6) }
            HStack {
                Text("Drag to reorder · changes live in Zig")
                Spacer()
                Text("revision \(model.revision)")
            }.font(.caption).foregroundStyle(.secondary).padding(20)
        }.onChange(of: env, initial: true) { _, value in model.core.environment(value) }
    }
    private func add() {
        if model.add(draft) { draft = ""; error = nil } else { error = "Enter a task of at most 4096 UTF-8 bytes." }
    }
}

private struct TodoRow: View {
    let row: TodoSnapshot
    @Environment(TodoModel.self) private var model
    @Environment(LabSettings.self) private var settings
    var body: some View {
        GeneratedTodoControls(title: row.title,
            isDone: Binding(get: { row.done }, set: { _ in withAnimation { model.toggle(row.id) } }),
            onDelete: { withAnimation { model.remove(row.id) } })
            .strikethrough(row.done).foregroundStyle(row.done ? .secondary : .primary)
            .padding(settings.compact ? 10 : 17)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .contextMenu {
                Button("Move to top") { if let first = model.rows.first { model.move(row.id, before: first.id) } }
                Button("Move to end") { model.move(row.id, before: 0) }
            }
    }
}
