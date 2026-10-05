import SwiftUI
import GongCore

/// The game world, cropped to the width the transition currently shows. Steps the game once per frame.
struct GameWorldView: View {
    @ObservedObject var controller: GameController
    let meeting: Meeting
    let date: Date
    let width: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderer = GameRenderer()

    var body: some View {
        let scale = CGFloat(RetroTheme.sceneScale)
        Group {
            if let image = frame() {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            }
        }
        .frame(width: CGFloat(width) * scale, height: CGFloat(NinjaGame.height) * scale)
        .accessibilityElement()
        .accessibilityLabel(L("Ninja game: dodge and deflect the shurikens."))
    }

    private func frame() -> CGImage? {
        controller.step(at: date, minutesToStart: meeting.start.timeIntervalSince(date) / 60)
        let world = renderer.render(controller.game, time: controller.game.runTime + controller.game.deathTime,
                                    shake: controller.shake(at: date), newHigh: controller.newHigh, reduceMotion: reduceMotion,
                                    petalTime: max(0, date.timeIntervalSince(controller.sceneClock.start)),
                                    best: controller.best, score: controller.lastScore,
                                    secondsToStart: max(0, meeting.start.timeIntervalSince(date)))
        return world.cropped(width: width).cgImage()
    }
}

/// Under the world while playing: the controls as pixel key caps, and the meeting countdown in the modal's gold.
struct GameHUD: View {
    @ObservedObject var controller: GameController
    let meeting: Meeting
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            KeyCap("← →"); label(L("WALK"))
            KeyCap("↑"); label(L("FLIP"))
            KeyCap("↓"); label(L("CROUCH / SLIDE"))
            KeyCap(L("SPACE")); label(L("STRIKE"))
            KeyCap("ENTER"); label(meeting.meetURL == nil ? L("CALENDAR") : L("JOIN"))
            Spacer(minLength: 8)
            Text(upperLocalized(Countdown.text(start: meeting.start, now: now)))
                .font(.pixel(RetroTheme.rowMetaSize)).foregroundStyle(RetroTheme.gold)
        }
        .lineLimit(1)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.pixel(11)).foregroundStyle(RetroTheme.muted).padding(.trailing, 6)
    }
}

/// A tiny keyboard key in the modal's pixel style.
struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.pixel(10, weight: .bold))
            .foregroundStyle(RetroTheme.text)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RetroTheme.button)
            .overlay(alignment: .bottom) { RetroTheme.buttonDark.frame(height: 2) }
            .padding(1).background(RetroTheme.ink)
    }
}
