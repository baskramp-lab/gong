import SwiftUI
import GongCore

enum BlockingAction { case join(URL), openCalendar, snooze, close }

/// Retro modal, layout B: scene left, meeting info right; overlapping meetings as compact rows below.
struct BlockingView: View {
    let meetings: [Meeting]
    let game: GameController
    let onAction: (Meeting, BlockingAction) -> Void
    static let maxRows = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { geo in
                VStack(spacing: RetroTheme.stackSpacing) {
                    // Fixed-size panels (RetroTheme), so every row lines up with the main panel.
                    if let first = meetings.first {
                        PrimaryMeetingPanel(meeting: first, now: context.date, game: game, onAction: onAction)
                            .frame(width: RetroTheme.panelWidth)   // height: the panel's own (it grows during the game)
                    }
                    // Overlapping meetings: at most three compact rows, the rest summarised.
                    ForEach(meetings.dropFirst().prefix(Self.maxRows)) { m in
                        CompactMeetingRow(meeting: m, now: context.date, onAction: onAction)
                            .frame(width: RetroTheme.panelWidth, height: RetroTheme.rowHeight)
                    }
                    if meetings.count - 1 > Self.maxRows {
                        Text(L("+%d MORE — SEE YOUR CALENDAR", meetings.count - 1 - Self.maxRows))
                            .font(.pixel(15)).foregroundStyle(RetroTheme.muted)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct PrimaryMeetingPanel: View {
    let meeting: Meeting
    let now: Date
    @ObservedObject var game: GameController
    let onAction: (Meeting, BlockingAction) -> Void

    /// Width of the info column in the scene layout: panel content minus the scene and the gap.
    private static let infoWidth = RetroTheme.panelWidth - 2 * RetroTheme.panelPadding
        - CGFloat(SceneLayout.modal.width * RetroTheme.sceneScale) - RetroTheme.sceneInfoGap

    var body: some View {
        // One layout for scene and game: the world widens to the right while the info column folds away.
        TimelineView(.animation(paused: !game.isActive)) { context in
            let p = game.progress(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: RetroTheme.sceneInfoGap * (1 - p)) {
                    if game.isActive {
                        GameWorldView(controller: game, meeting: meeting, date: context.date, width: game.viewWidth(at: context.date))
                    } else {
                        PixelSceneView(clock: game.sceneClock)
                    }
                    info
                        .frame(width: Self.infoWidth, alignment: .leading)
                        .frame(width: max(1, Self.infoWidth * (1 - p)), alignment: .leading)
                        .clipped()
                        .opacity(1 - p)
                }
                ZStack(alignment: .leading) {
                    sceneNote
                        .lineLimit(1).fixedSize()
                        .frame(width: game.lastScore == nil ? CGFloat(SceneLayout.modal.width * RetroTheme.sceneScale) : nil)
                        .opacity(1 - p)
                    if p > 0 { GameHUD(controller: game, meeting: meeting, now: now).opacity(p) }
                }
                .frame(height: 16)
                // during the game the meeting stays one click away, under the controls
                if p > 0 {
                    HStack(spacing: RetroTheme.buttonGap) {
                        MeetingButtons(meeting: meeting, onAction: onAction, part: .open, isDefault: false)
                        MeetingButtons(meeting: meeting, onAction: onAction, part: .later)
                    }
                    .padding(.top, 8)
                    .opacity(p)
                }
            }
            .padding(RetroTheme.panelPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: RetroTheme.primaryHeight + RetroTheme.gameButtonsHeight * p, alignment: .topLeading)
            .clipped()
            .pixelPanel()
        }
    }

    /// Under the scene: this meeting's score once the one game has been played.
    @ViewBuilder private var sceneNote: some View {
        if let score = game.lastScore {
            Text(L("SCORE %1$d · HI %2$d · NEXT TRY AT THE NEXT MEETING", score, game.best))
                .font(.pixel(11)).foregroundStyle(RetroTheme.gold)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(meeting.title)
                .font(.pixel(RetroTheme.titleSize, weight: .bold))
                .foregroundStyle(RetroTheme.text)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
            Text(upperLocalized(Countdown.text(start: meeting.start, now: now)))
                .font(.pixel(RetroTheme.countdownSize))
                .foregroundStyle(RetroTheme.gold)
            VStack(alignment: .leading, spacing: RetroTheme.buttonGap) {
                HStack(spacing: RetroTheme.buttonGap) {
                    // the default action keeps working (Enter) while the column is folded away during the game
                    MeetingButtons(meeting: meeting, onAction: onAction, part: .open)
                }
                HStack(spacing: RetroTheme.buttonGap) {
                    MeetingButtons(meeting: meeting, onAction: onAction, part: .later)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let first = meeting.description?.split(separator: "\n").first, !first.isEmpty {
                    Text(String(first)).font(.pixel(RetroTheme.metaSize)).foregroundStyle(RetroTheme.muted).lineLimit(1)
                }
                if !meeting.attendees.isEmpty {
                    Text(attendeeLine(meeting)).font(.pixel(RetroTheme.metaSize)).foregroundStyle(RetroTheme.muted.opacity(0.7)).lineLimit(1)
                }
            }
        }
    }
}

/// The modal's meeting actions: `.open` = join / agenda, `.later` = snooze / close. Shared by the info column and
/// the game-over overlay; only one of them carries the Enter shortcut.
struct MeetingButtons: View {
    enum Part { case open, later }
    let meeting: Meeting
    let onAction: (Meeting, BlockingAction) -> Void
    let part: Part
    var isDefault = true

    var body: some View {
        switch part {
        case .open:
            if let url = meeting.meetURL {
                Button(L("JOIN MEET")) { onAction(meeting, .join(url)) }
                    .buttonStyle(PixelButtonStyle(primary: true)).keyboardShortcut(isDefault ? .defaultAction : nil)
                Button(L("CALENDAR")) { onAction(meeting, .openCalendar) }
                    .buttonStyle(PixelButtonStyle())
            } else {
                Button(L("OPEN IN CALENDAR")) { onAction(meeting, .openCalendar) }
                    .buttonStyle(PixelButtonStyle(primary: true)).keyboardShortcut(isDefault ? .defaultAction : nil)
            }
        case .later:
            Button(L("SNOOZE 2 MIN")) { onAction(meeting, .snooze) }.buttonStyle(PixelButtonStyle())
            Button(L("CLOSE")) { onAction(meeting, .close) }.buttonStyle(PixelButtonStyle())
        }
    }
}

struct CompactMeetingRow: View {
    let meeting: Meeting
    let now: Date
    let onAction: (Meeting, BlockingAction) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(L("ALSO NOW")).font(.pixel(RetroTheme.rowLabelSize, weight: .bold)).foregroundStyle(RetroTheme.gold)
            Text(meeting.title)
                .font(.pixel(RetroTheme.rowTitleSize, weight: .semibold)).foregroundStyle(RetroTheme.text)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(upperLocalized(Countdown.text(start: meeting.start, now: now)))
                .font(.pixel(RetroTheme.rowMetaSize)).foregroundStyle(RetroTheme.muted).lineLimit(1)
            if let url = meeting.meetURL {
                Button(L("JOIN")) { onAction(meeting, .join(url)) }.buttonStyle(PixelButtonStyle())
            } else {
                Button(L("CALENDAR")) { onAction(meeting, .openCalendar) }.buttonStyle(PixelButtonStyle())
            }
            Button(L("CLOSE")) { onAction(meeting, .close) }.buttonStyle(PixelButtonStyle())
        }
        .padding(.horizontal, RetroTheme.rowPaddingX)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pixelPanel()
    }
}

private func attendeeLine(_ meeting: Meeting) -> String {
    let names = meeting.attendees.prefix(5).map { $0.name ?? $0.email }
    let more = meeting.attendees.count - names.count
    return names.joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
}

/// Small pixel panel on the other screens: mini gong, live countdown, pointer to the main screen.
struct SecondaryScreenView: View {
    let start: Date
    private static let gongImage = SceneRenderer.miniGong().cgImage()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: RetroTheme.sceneInfoGap) {
                if let img = Self.gongImage {
                    Image(decorative: img, scale: 1).resizable().interpolation(.none)
                        .frame(width: 52 * 3, height: 56 * 3)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(Self.headline(start: start, now: context.date))
                        .font(.pixel(RetroTheme.countdownSize * 1.4, weight: .bold))
                        .foregroundStyle(RetroTheme.gold)
                    Text(L("LOOK AT YOUR MAIN SCREEN"))
                        .font(.pixel(RetroTheme.metaSize))
                        .foregroundStyle(RetroTheme.muted)
                }
            }
            .padding(RetroTheme.panelPadding)
            .pixelPanel()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static func headline(start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes > 0 ? L("MEETING IN %d MIN", minutes) : L("MEETING STARTING")
    }
}
