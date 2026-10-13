import SwiftUI
import Foundation

@inline(never) private func consume<T>(_ input: T) {
    var value = input
    withUnsafePointer(to: &value) { zw_bench_consume($0) }
}
private struct Measurement: Encodable {
    let name: String
    let iterations: Int
    let samples_ns_per_op: [Double]
    var median_ns: Double { samples_ns_per_op.sorted()[samples_ns_per_op.count / 2] }
    enum CodingKeys: String, CodingKey { case name, iterations, samples_ns_per_op, median_ns }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(iterations, forKey: .iterations)
        try c.encode(samples_ns_per_op, forKey: .samples_ns_per_op); try c.encode(median_ns, forKey: .median_ns)
    }
}
@MainActor private func measure(_ name: String, _ count: Int, _ operation: (Int) -> Void) -> Measurement {
    for i in 0..<max(5, count / 20) { operation(i) }
    var samples: [Double] = []
    for _ in 0..<7 {
        let start = DispatchTime.now().uptimeNanoseconds
        for i in 0..<count { operation(i) }
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count))
    }
    return Measurement(name: name, iterations: count, samples_ns_per_op: samples)
}
private struct HandwrittenCard: View {
    let title: String
    let count: UInt64
    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: title)
            Text(verbatim: String(describing: count))
            HStack(spacing: 8) { Text(verbatim: "Typed"); Text(verbatim: "SwiftUI") }
        }
    }
}
// Keep the previous implementation as an in-process baseline for copy removal.
@MainActor private func legacyEditorSnapshot(_ text: String, core: CoreHandle) -> EditorSnapshot? {
    let bytes = Array(text.utf8) + [0]
    guard bytes.withUnsafeBufferPointer({ zw_editor_set(core.raw, $0.baseAddress!, $0.count - 1) }) != 0 else { return nil }
    return EditorSnapshot(text: core.read { zw_editor_text(core.raw, $0, $1) }, stats: zw_editor_stats(core.raw), revision: zw_revision(core.raw))
}
@main struct Bench {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let iterations = 100_000
        let strings = (0..<64).map { String(repeating: "Zig 👋 Swift ", count: 10) + String($0) }
        let enabled = \EnvironmentValues.isEnabled
        let scale = \EnvironmentValues.generatedScale
        var results: [Measurement] = []
        func add(_ name: String, _ count: Int = iterations, _ operation: (Int) -> Void) {
            results.append(measure(name, count, operation))
        }
        add("harness.consume") { consume(UInt64($0)) }
        add("abi.quad.zig") { consume(nativeQuad(UInt64($0))) }
        add("abi.quad.swift") { consume(reference_nativeQuad(UInt64($0))) }
        add("abi.state_uint.zig") { consume(nativeState(UInt64($0))) }
        add("abi.state_uint.swift") { consume(reference_nativeState(UInt64($0))) }
        add("abi.state_bool.zig") { consume(nativeStateBool($0 & 1 == 0)) }
        add("abi.state_bool.swift") { consume(reference_nativeStateBool($0 & 1 == 0)) }
        add("abi.state_double.zig") { consume(nativeStateDouble(Double($0))) }
        add("abi.state_double.swift") { consume(reference_nativeStateDouble(Double($0))) }
        add("abi.state_string.zig") { consume(nativeStateString(strings[$0 & 63])) }
        add("abi.state_string.swift") { consume(reference_nativeStateString(strings[$0 & 63])) }
        add("abi.environment_bool.zig") { _ in consume(nativeEnvironment(enabled)) }
        add("abi.environment_bool.swift") { _ in consume(reference_nativeEnvironment(enabled)) }
        add("abi.environment_double.zig") { _ in consume(nativeEnvironmentDouble(scale)) }
        add("abi.environment_double.swift") { _ in consume(reference_nativeEnvironmentDouble(scale)) }
        add("abi.constant_bool.zig") { consume(nativeConstantBool($0 & 1 == 0)) }
        add("abi.constant_bool.swift") { consume(reference_nativeConstantBool($0 & 1 == 0)) }
        add("abi.text_string.zig") { consume(nativeTextString(strings[$0 & 63])) }
        add("abi.text_string.swift") { consume(reference_nativeTextString(strings[$0 & 63])) }
        add("view.body.generated") { consume(GeneratedBenchmarkCard(title: strings[$0 & 63], count: UInt64($0)).body) }
        add("view.body.handwritten") { consume(HandwrittenCard(title: strings[$0 & 63], count: UInt64($0)).body) }

        // Root replacement + synchronous CPU layout, not display/GPU latency or FPS.
        let generated = NSHostingView(rootView: GeneratedBenchmarkCard(title: strings[0], count: 0))
        let handwritten = NSHostingView(rootView: HandwrittenCard(title: strings[0], count: 0))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = generated
        window.orderFront(nil)
        add("view.host_update.generated", 500) {
            generated.rootView = GeneratedBenchmarkCard(title: strings[$0 & 63], count: UInt64($0))
            generated.layoutSubtreeIfNeeded()
        }
        window.contentView = handwritten
        add("view.host_update.handwritten", 500) {
            handwritten.rootView = HandwrittenCard(title: strings[$0 & 63], count: UInt64($0))
            handwritten.layoutSubtreeIfNeeded()
        }
        window.close()

        for count in [100, 1000, 5000] {
            let core = CoreHandle()
            for i in 0..<count { _ = withUTF8("Task \(i)") { zw_todo_add(core.raw, $0, $1) } }
            let id = zw_todo_id(core.raw, count / 2)
            add("todo.toggle_core.\(count)", 1000) { _ in consume(zw_todo_toggle(core.raw, id)) }
            add("todo.toggle_snapshot_legacy.\(count)", count < 5000 ? 50 : 10) { _ in
                _ = zw_todo_toggle(core.raw, id)
                let rows = (0..<zw_todo_count(core.raw)).map { index in
                    let rowID = zw_todo_id(core.raw, index)
                    return TodoSnapshot(id: rowID, title: core.read { zw_todo_title(core.raw, rowID, $0, $1) }, done: zw_todo_done(core.raw, rowID) != 0)
                }
                consume(rows)
            }
            add("todo.toggle_snapshot_indexed.\(count)", 50) { _ in
                _ = zw_todo_toggle(core.raw, id)
                let rows = (0..<zw_todo_count(core.raw)).map { index in
                    let info = zw_todo_at(core.raw, index, nil, 0)
                    return TodoSnapshot(id: info.id, title: core.read { zw_todo_at(core.raw, index, $0, $1).title_bytes }, done: info.done != 0)
                }
                consume(rows)
            }
        }
        let model = TodoModel(seed: false)
        for i in 0..<1000 { _ = model.add("Task \(i)") }
        add("todo.callback_model.1000", 50) { _ in model.toggle(model.rows[500].id); consume(model.rows) }
        for size in [1024, 102400, 1048576, 8388608] {
            let core = CoreHandle()
            let a = String(repeating: "line words here\n", count: size / 16 + 1)
            let prefix = String(a.prefix(size - 1))
            let variants = [prefix + "a", prefix + "b"]
            let bytes = variants.map { Array($0.utf8) }
            var edit = 0
            add("editor.core_set_stats.\(size)", size > 1048576 ? 5 : 20) { _ in
                edit ^= 1
                bytes[edit].withUnsafeBufferPointer { buffer in
                    _ = zw_editor_set(core.raw, buffer.baseAddress!, buffer.count)
                    consume(zw_editor_stats(core.raw))
                }
            }
            add("editor.snapshot_legacy.\(size)", size > 1048576 ? 5 : 20) { _ in
                edit ^= 1
                consume(legacyEditorSnapshot(variants[edit], core: core))
            }
            add("editor.snapshot_reducer.\(size)", size > 1048576 ? 5 : 20) { _ in
                edit ^= 1
                consume(EditorReducer.replace(variants[edit], core: core))
            }
        }
        struct Report: Encodable {
            let os: String
            let samples = 7
            let notes = "ReleaseFast Zig / swiftc -O. Includes harness and destruction; warmup 5%, minimum 5 iterations. Sequential cases: small ratios need repeated runs. Swift baselines are noinline. Host timings cover synchronous CPU work, not GPU or input latency. Editor variants alternate to force edits."
            let results: [Measurement]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Report(os: ProcessInfo.processInfo.operatingSystemVersionString, results: results))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
