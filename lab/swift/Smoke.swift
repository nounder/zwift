import SwiftUI
import WebKit
import Observation

enum SmokeError: Error { case failed(String) }
@MainActor private final class Flag { var value = false }
func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw SmokeError.failed(message) }
}

@MainActor @Observable private final class BindingDriver {
    var input = "example.com"
    var output = ""
    var allowHTTP = false
    var accepted = false
}
private struct BindingProbe: View {
    let driver: BindingDriver
    @ZigAddress private var address: String
    var body: some View {
        Text(address)
            .onChange(of: driver.input, initial: true) { _, value in
                _address.environment(.init(dark: false, compact: false, allowHTTP: driver.allowHTTP))
                driver.accepted = _address.submit(value)
                // Also exercise the projected SwiftUI Binding.
                if driver.accepted { $address.wrappedValue = address }
            }
            .onChange(of: address, initial: true) { _, value in driver.output = value }
    }
}

@MainActor @Observable private final class NativeDriver {
    var seed: UInt64 = 7
    var tick = 0
    var identity = 0
    var enabled = true
    var observedEnabled = true
    var count: UInt64 = 0
}
private struct NativeProbe: View {
    let driver: NativeDriver
    @State private var count: UInt64
    @Environment private var enabled: Bool
    init(seed: UInt64, driver: NativeDriver) {
        self.driver = driver
        _count = nativeState(seed)
        _enabled = nativeEnvironment(\.isEnabled)
    }
    var body: some View {
        Text(verbatim: "\(count) / \(enabled)")
            .onChange(of: driver.tick) { _, _ in count &+= 1 }
            .onChange(of: count, initial: true) { _, value in driver.count = value }
            .onChange(of: enabled, initial: true) { _, value in driver.observedEnabled = value }
    }
}
private struct NativeProbeContainer: View {
    let driver: NativeDriver
    var body: some View {
        NativeProbe(seed: driver.seed, driver: driver).id(driver.identity).environment(\.isEnabled, driver.enabled)
    }
}

@MainActor @Observable private final class ScalarsDriver {
    var tick = 0
    var scale = 2.5
    var observedScale = 0.0
    var flag = false
    var number = 0.0
    var text = ""
    var seed = String(repeating: "Zig 👋 Łódź ", count: 100)
}
private struct ScalarsProbe: View {
    let driver: ScalarsDriver
    @State private var flag: Bool
    @State private var number: Double
    @State private var text: String
    @Environment private var scale: Double
    init(driver: ScalarsDriver) {
        self.driver = driver
        _flag = nativeStateBool(true)
        _number = nativeStateDouble(3.25)
        _text = nativeStateString(driver.seed)
        _scale = nativeEnvironmentDouble(\.generatedScale)
    }
    var body: some View {
        nativeTextString(text)
            .onChange(of: driver.tick) { _, _ in
                $flag.wrappedValue.toggle()
                $number.wrappedValue += 0.5
                $text.wrappedValue += "✓"
            }
            .onChange(of: flag, initial: true) { _, value in driver.flag = value }
            .onChange(of: number, initial: true) { _, value in driver.number = value }
            .onChange(of: text, initial: true) { _, value in driver.text = value }
            .onChange(of: scale, initial: true) { _, value in driver.observedScale = value }
    }
}
private struct ScalarsContainer: View {
    let driver: ScalarsDriver
    var body: some View { ScalarsProbe(driver: driver).environment(\.generatedScale, driver.scale) }
}
@MainActor @Observable private final class KeyedDriver {
    var items = [GeneratedItem(id: 10, title: "Ten"), GeneratedItem(id: 20, title: "Twenty")]
    var tick: UInt64 = 0
    var results: [UInt64: UInt64] = [:]
    var present = true
}
private struct KeyedContainer: View {
    let driver: KeyedDriver
    var body: some View {
        if driver.present {
            GeneratedKeyedList(items: driver.items, tick: driver.tick, report: { driver.results[$0] = $1 })
        }
    }
}

@main struct Smoke {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try require(MemoryLayout<State<UInt64>>.size == 16 && MemoryLayout<Environment<Bool>>.size == 9 && MemoryLayout<Text>.size == 32, "native wrapper layout assumptions")
        for seed in [UInt64(0), 42, UInt64.max - 1] {
            let q = nativeQuad(seed)
            try require(q.a == seed && q.b == seed &+ 1 && q.c == seed &+ 2 && q.d == seed &+ 3, "Swift four-register return")
        }
        // Exercise ownership of both short and long literal String representations.
        for i in 0..<10_000 { _ = nativeText(UInt64(i % 5)) }
        print("PASS native Swift ABI: four-register values, wrapping arithmetic, 10000 Text lifetimes")

        try require(MemoryLayout<State<Bool>>.size == 16 && MemoryLayout<State<Double>>.size == 16 && MemoryLayout<State<String>>.size == 24 && MemoryLayout<Environment<Double>>.size == 9 && MemoryLayout<Binding<Bool>>.size == 17, "new specialization layouts")
        for bits in [UInt64(0), 0x8000000000000000, 0x7ff8000000000042, 0xfff0000000000000] {
            try require(nativeStateDouble(Double(bitPattern: bits)).wrappedValue.bitPattern == bits, "Double exact bits including -0, NaN and infinity")
        }
        for i in 0..<10_000 {
            var source = i % 2 == 0 ? "tiny" : String(repeating: "Owned 👋 Łódź ", count: 20) + String(i)
            let expected = source
            let state = nativeStateString(source)
            let text = nativeTextString(source)
            source += "mutated"
            try require(state.wrappedValue == expected, "borrowed String retained independently")
            let binding = nativeConstantBool(i % 2 == 0)
            binding.wrappedValue = i % 2 != 0
            try require(binding.wrappedValue == (i % 2 == 0), "constant Binding ignores writes")
            try require(nativeStateBool(i % 2 == 0).wrappedValue == (i % 2 == 0), "Bool ABI return")
            withExtendedLifetime(text) {}
        }
        print("PASS Bool/Double/String state values, exact floating bits, 10000 dynamic String/Binding ownership cycles")

        let todos = TodoModel(seed: false)
        try require(todos.add("First 👋") && todos.add("Second"), "todo add")
        let id = todos.rows[0].id
        // Observation must receive writes originating in the Zig callback.
        let notified = Flag()
        withObservationTracking { _ = todos.rows } onChange: { MainActor.assumeIsolated { notified.value = true } }
        todos.toggle(id)
        try require(notified.value && todos.rows[0].done, "callback invalidates Swift Observation")
        todos.move(id, before: 0)
        try require(todos.rows.last?.id == id, "todo identity reorder")
        todos.remove(id)
        try require(todos.rows.count == 1, "todo delete")
        let independent = TodoModel(seed: false)
        try require(independent.rows.isEmpty, "per-window store isolation")
        for _ in 0..<1000 { _ = TodoModel() }
        print("PASS callback → @Observable; add/check/reorder/delete; independent stores; callback teardown")

        let core = CoreHandle()
        let snapshot = EditorReducer.replace("Hi 👋\nZig", core: core)!
        try require(snapshot.stats.words == 3 && snapshot.stats.lines == 2 && snapshot.stats.scalars == 8 && snapshot.stats.bytes == 11, "editor UTF-8 snapshot")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: temp) }
        let document = PlainTextFile(text: snapshot.text)
        // Exercise the FileDocument encoding/decoding without an interactive panel.
        try document.encodedFileWrapper().write(to: temp, options: .atomic, originalContentsURL: nil)
        let restored = try PlainTextFile.decode(Data(contentsOf: temp))
        try require(restored == snapshot.text, "editor file round trip")
        try require(EditorReducer.replace("", core: core)?.stats.lines == 1, "empty document")
        print("PASS @State snapshot reducer; Unicode statistics; UTF-8 file round trip")

        let bridged = NSString(string: String(repeating: "Café 👩🏽‍💻 ", count: 100)) as String
        for input in ["", "a\0b", "e\u{301} 👋", bridged, String(repeating: "long UTF-8 👋\n", count: 10_000)] {
            let expected = Array(input.utf8)
            let borrowed = withUTF8(input) { Array(UnsafeBufferPointer(start: $0, count: $1)) }
            try require(borrowed == expected, "scoped UTF-8 preserves empty, NUL, Unicode and bridged input")
            let retained = EditorReducer.replace(input, core: core)!
            try require(Array(retained.text.utf8) == expected && retained.stats.bytes == expected.count, "snapshot keeps the exact accepted bytes")
            let revision = retained.revision
            try require(EditorReducer.replace(input, core: core)?.revision == revision, "unchanged editor input preserves revision")
            _ = EditorReducer.replace("subsequent edit", core: core)
            try require(Array(retained.text.utf8) == expected, "snapshot lifetime is independent of subsequent core edits")
            _ = EditorReducer.replace(input, core: core)
            try require(Array(core.read { zw_editor_text(core.raw, $0, $1) }.utf8) == expected, "Zig owns a copy after the borrowed call returns")
        }
        print("PASS borrowed UTF-8 and reused editor snapshots: empty/NUL/Unicode/NSString/large input, unchanged revisions and independent lifetimes")

        let driver = BindingDriver()
        let probe = window(BindingProbe(driver: driver))
        defer { probe.close() }
        try await until("installed DynamicProperty binding") { driver.output == "https://example.com" }
        driver.input = "http://example.com"
        try await Task.sleep(for: .milliseconds(100))
        try require(!driver.accepted && driver.output == "https://example.com", "rejected mutation leaves installed state unchanged")
        driver.allowHTTP = true; driver.input = "http://localhost:8080"
        try await until("environment changes Zig URL policy") { driver.output == "http://localhost:8080" }
        print("PASS installed DynamicProperty / @State identity / projected Binding / environment policy")

        let nativeDriver = NativeDriver()
        let nativeWindow = window(NativeProbeContainer(driver: nativeDriver))
        defer { nativeWindow.close() }
        try await until("Zig-created State installation") { nativeDriver.count == 7 }
        nativeDriver.tick += 1
        try await until("Zig-created State mutation") { nativeDriver.count == 8 }
        nativeDriver.seed = 99; nativeDriver.enabled = false
        try await until("Zig-created Environment propagation") { !nativeDriver.observedEnabled }
        try require(nativeDriver.count == 8, "view reinitialization preserves installed State")
        nativeDriver.identity += 1
        try await until("new view identity resets native State") { nativeDriver.count == 99 }
        nativeDriver.enabled = true
        try await until("native Environment propagates twice") { nativeDriver.observedEnabled }
        print("PASS Zig-created native State and Environment: installation, mutation, retained identity, reset, propagation")

        let scalarDriver = ScalarsDriver()
        let originalSeed = scalarDriver.seed
        let scalarWindow = window(ScalarsContainer(driver: scalarDriver))
        defer { scalarWindow.close() }
        try await until("new native wrapper installation") { scalarDriver.flag && scalarDriver.number == 3.25 && scalarDriver.text == originalSeed && scalarDriver.observedScale == 2.5 }
        scalarDriver.seed = "replaced input"
        scalarDriver.tick += 1
        scalarDriver.scale = 7.75
        try await until("projected native bindings and Double environment") { !scalarDriver.flag && scalarDriver.number == 3.75 && scalarDriver.text == originalSeed + "✓" && scalarDriver.observedScale == 7.75 }
        print("PASS installed native Bool/Double/String state, projected bindings, String seed identity and Double environment")

        let keyed = KeyedDriver()
        let keyedWindow = window(KeyedContainer(driver: keyed))
        defer { keyedWindow.close() }
        try await until("generated initial keyed state") { keyed.results == [10: 10, 20: 20] }
        keyed.tick += 1
        try await until("generated action mutation") { keyed.results == [10: 11, 20: 21] }
        keyed.items.reverse()
        try await Task.sleep(for: .milliseconds(100))
        keyed.tick += 1
        try await until("generated state follows reordered identity") { keyed.results == [10: 12, 20: 22] }
        keyed.items.removeAll { $0.id == 10 }
        try await Task.sleep(for: .milliseconds(100))
        keyed.results.removeValue(forKey: 10)
        keyed.items.append(GeneratedItem(id: 10, title: "Reinserted"))
        try await until("removed generated row gets fresh state") { keyed.results == [10: 10, 20: 22] }
        keyed.present = false
        try await Task.sleep(for: .milliseconds(100))
        keyed.results = [:]
        keyed.present = true
        try await until("branch reinsertion creates new storage") { keyed.results == [10: 10, 20: 20] }
        print("PASS typed Zig views: generated actions, keyed reordering, removal/reinsertion and conditional identity")

        let browser = BrowserModel()
        let webWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        webWindow.isReleasedWhenClosed = false
        webWindow.contentView = browser.web
        webWindow.orderFront(nil)
        defer { webWindow.close() }
        try await until("WebKit local start page") { browser.finishedLoads > 0 }
        let title = try await browser.web.evaluateJavaScript("document.title") as? String
        try require(title == "Zwift / Start", "actual WKWebView document")
        browser.navigate("javascript:alert(1)")
        try require(browser.error != nil, "unsupported URL scheme rejected")
        browser.allowHTTP = true
        try require(BrowserModel.allowed(URL(string: "http://localhost:8000")!, allowHTTP: browser.allowHTTP), "HTTP policy")
        browser.home()
        try await until("second WebKit load") { browser.finishedLoads > 1 }
        print("PASS actual WebKit load, page title, navigation policy and reload")
        if let base = ProcessInfo.processInfo.environment["ZWIFT_TEST_URL"] {
            browser.allowHTTP = false
            browser.web.load(URLRequest(url: URL(string: base + "/first")!))
            try await until("delegate enforces HTTP policy") { browser.error?.contains("blocked") == true }
            browser.allowHTTP = true
            browser.navigate(base + "/first")
            do { try await until("HTTP navigation") { browser.title == "First" && !browser.isLoading } }
            catch {
                let page = try? await browser.web.evaluateJavaScript("document.documentElement.outerHTML")
                throw SmokeError.failed("HTTP navigation: error=\(browser.error ?? "none") title=\(browser.title) url=\(browser.url) loading=\(browser.isLoading) loads=\(browser.finishedLoads) document=\(String(describing: page))")
            }
            _ = try await browser.web.evaluateJavaScript("document.querySelector('a').click()")
            try await until("WebKit link navigation") { browser.title == "Second" && !browser.isLoading }
            try require(browser.canGoBack, "back navigation enabled")
            browser.web.goBack()
            try await until("WebKit back") { browser.title == "First" && browser.canGoForward && !browser.isLoading }
            browser.web.goForward()
            try await until("WebKit forward") { browser.title == "Second" && !browser.isLoading }
            let loads = browser.finishedLoads
            browser.web.reload()
            try await until("WebKit reload") { browser.finishedLoads > loads && !browser.isLoading }
            print("PASS local HTTP: real navigation delegate, links, history back/forward, reload")
        }

        if CommandLine.arguments.count > 1 {
            let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try await capture(LabShell(kind: 0) { TodoRoot() }, to: dir.appendingPathComponent("todo.png"))
            try await capture(LabShell(kind: 1) { EditorRoot() }, to: dir.appendingPathComponent("editor.png"))
            try await capture(LabShell(kind: 2) { BrowserRoot() }, to: dir.appendingPathComponent("browser.png"))
            print("PASS all three SwiftUI roots rendered; screenshots: \(dir.path)")
        }
        print("All lab smoke tests passed")
    }
    @MainActor private static func until(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw SmokeError.failed("Timed out: " + description)
    }
    @MainActor private static func window<V: View>(_ view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        return window
    }
    @MainActor private static func capture<V: View>(_ view: V, to url: URL) async throws {
        let win = window(view)
        defer { win.close() }
        try await Task.sleep(for: .milliseconds(400))
        let content = win.contentView!
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw SmokeError.failed("bitmap allocation") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SmokeError.failed("PNG encoding") }
        try png.write(to: url)
    }
}
