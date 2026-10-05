import AppKit
import SwiftUI
import GongCore

/// Borderless window that can take keyboard focus.
final class BlockingWindow: NSWindow {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
    override func cancelOperation(_ sender: Any?) { /* Esc does nothing */ }
}

/// One dimmed window per screen; the primary one (where the mouse is) hosts the modal panel.
final class BlockingWindowController {
    private var windows: [NSWindow] = []
    private var hosting: NSHostingView<AnyView>?
    private var secondaries: [NSHostingView<AnyView>] = []
    private var lastMeetings: [Meeting] = []
    private var lastAction: ((Meeting, BlockingAction) -> Void)?
    /// Shared by the scene animation and the gong sound; lives as long as the modal is visible.
    private var clock = StrikeClock(start: Date())
    private let sound: GongSoundPlayer
    private let bestGameScore: () -> Int
    private let saveBestGameScore: (Int) -> Void
    private var game: GameController?
    /// The meeting the current game belongs to (the first one shown when it was made).
    private var gameMeetingID: String?
    /// One game per meeting: meetings whose game has been played (kept for the app's lifetime, so snoozing
    /// and re-showing the same meeting does not give a new chance).
    private var playedMeetings: Set<String> = []
    private var keyMonitor: Any?

    var isVisible: Bool { !windows.isEmpty }

    init(sound: GongSoundPlayer, bestGameScore: @escaping () -> Int = { 0 },
         saveBestGameScore: @escaping (Int) -> Void = { _ in }) {
        self.sound = sound
        self.bestGameScore = bestGameScore
        self.saveBestGameScore = saveBestGameScore
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isVisible, let action = self.lastAction else { return }
            self.teardown()
            self.build(meetings: self.lastMeetings, onAction: action)
            self.focusPrimary()
        }
    }

    func show(meetings: [Meeting], onAction: @escaping (Meeting, BlockingAction) -> Void) {
        lastMeetings = meetings
        lastAction = onAction
        if windows.isEmpty {
            clock = StrikeClock(start: Date())
            game = makeGame(for: meetings.first?.id)
            if keyMonitor == nil { keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
                guard let game = self?.game, e.window === self?.windows.first else { return e }
                return game.handle(e) ? nil : e
            } }
            build(meetings: meetings, onAction: onAction)
            sound.start(clock: clock)
        } else {
            // Another meeting moved to the front (the first was closed or snoozed): it gets its own game,
            // unless a run is in progress.
            if meetings.first?.id != gameMeetingID, game?.isMidRun != true {
                game?.exit()
                game = makeGame(for: meetings.first?.id)
            }
            hosting?.rootView = AnyView(panel(meetings: meetings, onAction: onAction))
            let start = Self.firstStart(meetings)
            secondaries.forEach { $0.rootView = AnyView(SecondaryScreenView(start: start)) }
        }
        focusPrimary()
    }

    private func makeGame(for id: String?) -> GameController {
        gameMeetingID = id
        return GameController(sound: sound, best: bestGameScore(), clock: clock,
                              canPlay: id.map { !playedMeetings.contains($0) } ?? true,
                              saveBest: saveBestGameScore,
                              onPlayed: { [weak self] in if let id { self?.playedMeetings.insert(id) } })
    }

    private static func firstStart(_ meetings: [Meeting]) -> Date { meetings.map(\.start).min() ?? Date() }

    func hide() {
        game?.exit()
        game = nil
        gameMeetingID = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        sound.stop()
        teardown()
    }

    private func focusPrimary() {
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        hosting = nil
        secondaries = []
    }

    private func panel(meetings: [Meeting], onAction: @escaping (Meeting, BlockingAction) -> Void) -> some View {
        let clock = self.clock
        let game = self.game ?? GameController(sound: sound, best: bestGameScore(), clock: clock, saveBest: saveBestGameScore)
        return GeometryReader { geo in
            // Panels have fixed sizes and are centred on the screen.
            BlockingView(meetings: meetings, game: game, onAction: onAction)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func build(meetings: [Meeting], onAction: @escaping (Meeting, BlockingAction) -> Void) {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? screens.first else { return }
        let firstStart = Self.firstStart(meetings)
        for screen in screens {
            let w = BlockingWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.backgroundColor = NSColor.black.withAlphaComponent(RetroTheme.screenDim)
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.setFrame(screen.frame, display: true)
            w.allowsKey = (screen == primary)
            if screen == primary {
                let hv = NSHostingView(rootView: AnyView(panel(meetings: meetings, onAction: onAction)))
                hv.frame = NSRect(origin: .zero, size: screen.frame.size)
                w.contentView = hv
                hosting = hv
                windows.insert(w, at: 0)
            } else {
                let hv = NSHostingView(rootView: AnyView(SecondaryScreenView(start: firstStart)))
                w.contentView = hv
                secondaries.append(hv)
                windows.append(w)
            }
            w.orderFrontRegardless()
        }
    }
}
