// Development oracle only. Never compiled or linked by lab-native.
import SwiftUI

struct ZigRoot: View {
    typealias Body = Text
    var body: Text { return Text(verbatim: "SwiftUI View and App emitted by Zig") }
}

@main struct ZigApp: App {
    typealias Body = WindowGroup<ZigRoot>
    init() {}
    // Explicit return avoids a redundant SceneBuilder copy of the same type.
    var body: Body { return WindowGroup { ZigRoot() } }
}
