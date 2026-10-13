import SwiftUI
import AppKit
import Observation

@MainActor final class LabAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let output = ProcessInfo.processInfo.environment["ZWIFT_LAUNCH_PROBE"] {
            Task { @MainActor in
                try await Task.sleep(for: .seconds(1))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                      let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                do { try png.write(to: URL(fileURLWithPath: output)) } catch { exit(1) }
                print("PASS Swift App entry point: \(window.title), visible window \(Int(view.bounds.width))×\(Int(view.bounds.height))")
                NSApp.terminate(nil)
            }
        }
    }
}

@MainActor @Observable final class LabSettings {
    var compact = false
    var allowHTTP = false
    var appearance = 0
}

struct LabEnvironment: Equatable {
    let dark: Bool
    let compact: Bool
    let allowHTTP: Bool
    var abi: ZWEnvironment { ZWEnvironment(dark: dark ? 1 : 0, compact: compact ? 1 : 0, allow_http: allowHTTP ? 1 : 0) }
}

// Main-actor ownership is enforced in Swift. C callbacks are synchronous and may
// read committed state, but must not recursively mutate it or destroy the store.
@MainActor final class CoreHandle {
    nonisolated(unsafe) let raw: UnsafeMutableRawPointer
    init() {
        guard let raw = zw_create() else { fatalError("Unable to allocate Zig store") }
        self.raw = raw
    }
    deinit { zw_observe(raw, nil, nil); zw_destroy(raw) }
    func read(_ f: (UnsafeMutablePointer<UInt8>?, Int) -> Int) -> String {
        let length = f(nil, 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let copied = bytes.withUnsafeMutableBufferPointer { f($0.baseAddress, $0.count) }
        precondition(copied == length, "Core must stay on the main actor during snapshot reads")
        return String(decoding: bytes, as: UTF8.self)
    }
    func environment(_ value: LabEnvironment) { zw_environment(raw, value.abi) }
}

func withUTF8<T>(_ text: String, _ body: (UnsafePointer<UInt8>, Int) -> T) -> T {
    // Zig consumes or copies these bytes synchronously; the pointer must not escape.
    // withUTF8 may materialize storage for a noncontiguous/bridged String.
    var contiguous = text
    return contiguous.withUTF8 { bytes in
        if let base = bytes.baseAddress { return body(base, bytes.count) }
        // Keep the nonnull C ABI contract even if an empty buffer has no address.
        var empty: UInt8 = 0
        return withUnsafePointer(to: &empty) { body($0, 0) }
    }
}

struct LabShell<Content: View>: View {
    let kind: UInt64
    @ViewBuilder let content: () -> Content
    @State private var settings = LabSettings()
    private var accent: Color { kind == 0 ? .indigo : kind == 1 ? .orange : .teal }
    private var approach: String { ["01 / OBSERVATION + CALLBACKS", "02 / STATE + VALUE SNAPSHOTS", "03 / DYNAMIC PROPERTY + BINDING"][Int(kind)] }
    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle().fill(accent).frame(width: 7, height: 7)
                        Text("ZWIFT LAB").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    }.foregroundStyle(.secondary)
                    // This is an actual SwiftUI.Text returned through the Swift ABI
                    // by machine code emitted from lab/abi/native.zig.
                    nativeText(kind).font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text(approach).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("Auto").tag(0); Text("Light").tag(1); Text("Dark").tag(2)
                    }.pickerStyle(.segmented).frame(width: 155, height: 24)
                    Toggle("Compact", isOn: $settings.compact).toggleStyle(.switch).controlSize(.small).frame(height: 24)
                }
            }.fixedSize(horizontal: false, vertical: true).padding(24)
            Divider()
            content().environment(settings).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            GeneratedStatePanel().padding(.horizontal, 24).padding(.vertical, 8)
            Divider()
            HStack {
                Label("Zig 0.16 → SwiftUI", systemImage: "arrow.triangle.branch")
                Spacer()
                Text("Typed Zig views · native Swift ABI")
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
        }
        .tint(accent)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.appearance == 0 ? nil : settings.appearance == 1 ? .light : .dark)
        .frame(minWidth: 650, minHeight: 480)
    }
}
