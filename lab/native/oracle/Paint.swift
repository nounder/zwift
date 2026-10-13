import SwiftUI
struct Surface: NSViewRepresentable {
 typealias NSViewType = NSView
 typealias Coordinator = Void
 func makeNSView(context: Context) -> NSView { NSView(frame: NSRect(x: 0,y: 0,width: 800,height: 600)) }
 func updateNSView(_ view: NSView, context: Context) {}
 static func dismantleNSView(_ view: NSView, coordinator: ()) {}
}
