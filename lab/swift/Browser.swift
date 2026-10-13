import SwiftUI
import WebKit
import Observation

// SwiftUI installs the nested @State storage and invalidates readers when the
// revision changes. Zig owns the address; State owns identity and invalidation.
@MainActor @propertyWrapper struct ZigAddress: DynamicProperty {
    @State private var core = CoreHandle()
    @State private var revision: UInt64 = 0
    var wrappedValue: String {
        get { _ = revision; return core.read { zw_browser_url(core.raw, $0, $1) } }
        nonmutating set { _ = submit(newValue) }
    }
    var projectedValue: Binding<String> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
    @discardableResult func submit(_ input: String) -> Bool {
        guard withUTF8(input, { zw_browser_navigate(core.raw, $0, $1) }) != 0 else { return false }
        revision = zw_revision(core.raw)
        return true
    }
    func environment(_ value: LabEnvironment) { core.environment(value); revision = zw_revision(core.raw) }
}

@MainActor @Observable final class BrowserModel: NSObject, WKNavigationDelegate {
    @ObservationIgnored let web = WKWebView(frame: .zero)
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    var title = "Start here"
    var url = "about:blank"
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var progress = 0.0
    var error: String?
    var allowHTTP = false
    var finishedLoads = 0
    override init() {
        super.init()
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        observe(\.estimatedProgress)
        observe(\.title)
        observe(\.url)
        observe(\.canGoBack)
        observe(\.canGoForward)
        observe(\.isLoading)
        home()
    }
    private func observe<Value>(_ key: KeyPath<WKWebView, Value>) {
        observations.append(web.observe(key, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.sync() }
        })
    }
    func home() {
        error = nil
        web.loadHTMLString(Self.homeHTML, baseURL: nil)
    }
    func navigate(_ address: String) {
        guard let value = URL(string: address), Self.allowed(value, allowHTTP: allowHTTP) else { error = "Enter a valid HTTP(S) URL."; return }
        error = nil
        if address == "about:blank" { home() } else { web.load(URLRequest(url: value)) }
    }
    static func allowed(_ url: URL, allowHTTP: Bool) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard let host = url.host, !host.isEmpty else { return false }
        return url.scheme?.lowercased() == "https" || (allowHTTP && url.scheme?.lowercased() == "http")
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, Self.allowed(url, allowHTTP: allowHTTP) else {
            error = "Navigation blocked. Use HTTPS, or enable HTTP for local development."
            decisionHandler(.cancel); return
        }
        if action.targetFrame == nil { decisionHandler(.cancel); webView.load(action.request); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { isLoading = true; error = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishedLoads += 1; isLoading = false; sync()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = "The web process stopped. Reload to try again."; isLoading = false }
    private func failed(_ failure: Error) {
        isLoading = false
        if (failure as NSError).code != NSURLErrorCancelled { error = failure.localizedDescription }
        sync()
    }
    private func sync() {
        title = web.title ?? "Untitled"
        url = web.url?.absoluteString ?? "about:blank"
        canGoBack = web.canGoBack; canGoForward = web.canGoForward
        isLoading = web.isLoading; progress = web.estimatedProgress
    }
    static let homeHTML = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width"><title>Zwift / Start</title>
    <style>:root{color-scheme:light dark}body{font:16px -apple-system;margin:0;padding:60px 48px;line-height:1.6}small{letter-spacing:3px;color:#699b94}h1{font-size:42px;letter-spacing:-1.5px;line-height:1.15;max-width:480px}p{color:#888;max-width:450px}a{display:inline-block;margin:12px 12px 0 0;padding:9px 17px;border:1px solid #8885;border-radius:9px;color:inherit;text-decoration:none}</style></head>
    <body><small>YOUR SMALL CORNER OF THE WEB</small><h1>Where would you<br>like to go?</h1><p>A native WebKit view, a SwiftUI shell, and a Zig-owned address. Enter a URL above to begin.</p><a href="https://example.com">Example page ↗</a><a href="https://ziglang.org">Zig ↗</a><a href="https://www.swift.org">Swift ↗</a></body></html>
    """
}

private struct WebSurface: NSViewRepresentable {
    let model: BrowserModel
    func makeNSView(context: Context) -> WKWebView { model.web }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: ()) { view.stopLoading() }
}

struct BrowserRoot: View {
    @ZigAddress private var destination: String
    @State private var model = BrowserModel()
    @State private var draft = ""
    @Environment(LabSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    private var env: LabEnvironment { .init(dark: scheme == .dark, compact: settings.compact, allowHTTP: settings.allowHTTP) }
    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            GeneratedBrowserControls(address: $draft, canGoBack: model.canGoBack,
                canGoForward: model.canGoForward, isLoading: model.isLoading,
                onBack: { model.web.goBack() }, onForward: { model.web.goForward() },
                onReload: { if model.isLoading { model.web.stopLoading() } else { model.web.reload() } },
                onGo: { go() }, onHome: { model.home(); draft = ""; _ = _destination.submit("about:blank") })
                .padding(settings.compact ? 10 : 16)
            if model.isLoading { ProgressView(value: model.progress).progressViewStyle(.linear).frame(height: 2) }
            if let error = model.error { HStack { Image(systemName: "exclamationmark.triangle"); Text(error); Spacer() }.font(.caption).foregroundStyle(.orange).padding(10) }
            WebSurface(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(model.title).lineLimit(1)
                Spacer()
                Toggle("Allow HTTP", isOn: $settings.allowHTTP).toggleStyle(.switch).controlSize(.mini)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .onChange(of: env, initial: true) { _, value in _destination.environment(value); model.allowHTTP = value.allowHTTP }
        .onChange(of: model.url) { _, value in draft = value == "about:blank" ? "" : value }
    }
    private func go() {
        guard _destination.submit(draft) else { model.error = "Invalid address. Use HTTPS, or enable HTTP for local development."; return }
        draft = destination
        model.navigate(destination)
    }
}
