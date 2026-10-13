import SwiftUI
import UniformTypeIdentifiers

struct EditorSnapshot {
    var text = ""
    var stats = ZWStats(bytes: 0, scalars: 0, words: 0, lines: 1)
    var revision: UInt64 = 0
}

@MainActor enum EditorReducer {
    static func replace(_ text: String, core: CoreHandle) -> EditorSnapshot? {
        guard withUTF8(text, { zw_editor_set(core.raw, $0, $1) }) != 0 else { return nil }
        // The core accepts the exact UTF-8 input without normalizing it.
        return EditorSnapshot(text: text, stats: zw_editor_stats(core.raw), revision: zw_revision(core.raw))
    }
}

struct PlainTextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        self.text = try Self.decode(configuration.file.regularFileContents)
    }
    static func decode(_ data: Data?) throws -> String {
        guard let data, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }
    func encodedFileWrapper() -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { encodedFileWrapper() }
}

struct EditorRoot: View {
    @State private var core = CoreHandle()
    @State private var snapshot = EditorSnapshot()
    @State private var savedText = ""
    @State private var exportedText = ""
    @State private var filename = "Untitled.txt"
    @State private var fontSize = 15.0
    @State private var importing = false
    @State private var exporting = false
    @State private var confirmOpen = false
    @State private var message = "UTF-8 plain text · Cmd-O to open, Cmd-S to save"
    @Environment(LabSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    private var env: LabEnvironment { .init(dark: scheme == .dark, compact: settings.compact, allowHTTP: settings.allowHTTP) }
    private var text: Binding<String> { Binding(get: { snapshot.text }, set: { _ = replace($0) }) }
    private var dirty: Bool { snapshot.text != savedText }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.plaintext").foregroundStyle(.orange)
                Text(filename + (dirty ? " •" : "")).font(.subheadline.weight(.medium))
                Spacer()
                Button("Open…", systemImage: "folder") { if dirty { confirmOpen = true } else { importing = true } }.keyboardShortcut("o")
                Button("Save…", systemImage: "square.and.arrow.down") { exportedText = snapshot.text; exporting = true }.keyboardShortcut("s")
                    .buttonStyle(.borderedProminent)
            }.padding(settings.compact ? 12 : 20)
            Divider()
            TextEditor(text: text)
                .font(.system(size: fontSize, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(settings.compact ? 12 : 24)
                .background(Color(nsColor: .textBackgroundColor))
                .accessibilityIdentifier("editor-text")
            Divider()
            GeneratedEditorStats(words: snapshot.stats.words, lines: snapshot.stats.lines,
                scalars: snapshot.stats.scalars, bytes: snapshot.stats.bytes, fontSize: $fontSize)
                .padding(.horizontal, 24).padding(.vertical, 16)
            HStack { Text(message); Spacer(); Text("revision \(snapshot.revision)") }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 16)
        }
        .onChange(of: env, initial: true) { _, value in core.environment(value) }
        .confirmationDialog("Discard current edits and open another file?", isPresented: $confirmOpen) {
            Button("Discard and open…", role: .destructive) { importing = true }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8 * 1024 * 1024 else { message = "Prototype limit: open text files up to 8 MiB."; return }
                let value = try String(contentsOf: url, encoding: .utf8)
                guard replace(value) else { return }
                savedText = value; filename = url.lastPathComponent
                message = "Opened \(filename)"
            } catch { message = "Open failed: \(error.localizedDescription)" }
        }
        .fileExporter(isPresented: $exporting, document: PlainTextFile(text: exportedText), contentType: .plainText, defaultFilename: filename) { result in
            do { let url = try result.get(); savedText = exportedText; filename = url.lastPathComponent; message = "Saved \(filename)" }
            catch { message = "Save failed: \(error.localizedDescription)" }
        }
    }
    @discardableResult private func replace(_ value: String) -> Bool {
        guard let next = EditorReducer.replace(value, core: core) else { message = "Zig could not accept this edit."; return false }
        snapshot = next
        return true
    }
}
