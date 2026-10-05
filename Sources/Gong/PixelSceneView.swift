import SwiftUI
import GongCore

/// The animated ninja-and-gong scene at a fixed whole-number scale, so pixels stay crisp.
struct PixelSceneView: View {
    let clock: StrikeClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderer = SceneRenderer()
    private let layout = SceneLayout.modal

    var body: some View {
        let scale = CGFloat(RetroTheme.sceneScale)
        TimelineView(.animation) { context in
            if let image = frame(at: context.date) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .frame(width: CGFloat(layout.width) * scale, height: CGFloat(layout.height) * scale)
        .accessibilityElement()
        .accessibilityLabel(L("Ninja striking the gong"))
    }

    private func frame(at date: Date) -> CGImage? {
        let state = StrikeTimeline.state(cycleTime: clock.cycleTime(at: date),
                                         time: max(0, date.timeIntervalSince(clock.start)),
                                         reduceMotion: reduceMotion, layout: layout)
        return renderer.render(state).cgImage()
    }
}
