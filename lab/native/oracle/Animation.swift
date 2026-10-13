import SwiftUI
@_silgen_name("draw_native") func drawNative(_ context: CGContext, _ width: Double, _ height: Double, _ time: Double)
struct Motion: View {
 typealias Body = TimelineView<AnimationTimelineSchedule, Canvas<EmptyView>>
 var body: Body {
  return TimelineView(.animation(minimumInterval: 1.0/60)) { (timeline: Body.Context) in
   let time = timeline.date.timeIntervalSinceReferenceDate
   return Canvas { context, size in
    context.withCGContext { cg in drawNative(cg, size.width, size.height, time) }
   }
  }
 }
}
