import AppKit
import SwiftUI
import ServiceManagement
import GongCore

@MainActor
final class AppCoordinator {
    private let settingsFile = JSONFile<AppSettings>(url: AppPaths.settingsFile)
    private let stateFile = JSONFile<PersistedState>(url: AppPaths.stateFile)
    private var settings: AppSettings
    private let feed: CalendarFeed
    private let scheduler: Scheduler
    private let notifier = Notifier()
    private let sound: GongSoundPlayer
    private var blocking: BlockingWindowController!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController?
    private var meetings: [Meeting] = []
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var allowQuit = false
    private var icalURL: String?
    private var isRefreshing = false
    private var pendingRefresh = false
    private var activity: NSObjectProtocol?

    var isBlocking: Bool { blocking.isVisible }
    /// Whose calendar this is: the `myEmail` setting, else the address in the secret iCal URL.
    private var myEmail: String { CalendarIdentity.myEmail(setting: settings.myEmail, icalURL: icalURL) }
    /// The menu's demo modal is up (not a real meeting): ticks must not hide it.
    private var demoActive = false

    init() {
        let s = settingsFile.load(default: .default)
        settings = s
        // Materialise defaults so Bas can edit the file — but only the first time; otherwise a hand-edited
        // file with a JSON typo silently falls back to `.default` on load and then gets overwritten here.
        if !FileManager.default.fileExists(atPath: AppPaths.settingsFile.path) {
            try? settingsFile.save(s)
        }
        let persisted = stateFile.load(default: PersistedState())
        feed = CalendarFeed(cacheURL: AppPaths.feedCacheFile)
        scheduler = Scheduler(config: s.schedulerConfig, states: persisted.states, pauseUntil: persisted.pauseUntil, now: Date.init)
        sound = GongSoundPlayer(enabled: s.soundEnabled)
        blocking = BlockingWindowController(
            sound: sound,
            bestGameScore: { [weak self] in self?.settings.bestGameScore ?? 0 },
            saveBestGameScore: { [weak self] s in self?.updateSettings { $0.bestGameScore = s } })
    }

    // MARK: - Lifecycle

    func start() {
        statusBar = StatusBarController(actions: .init(
            pauseMinutes: { [weak self] minutes in self?.pause(until: Date().addingTimeInterval(Double(minutes) * 60)) },
            pauseToday: { [weak self] in
                let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
                    ?? Date().addingTimeInterval(86_400)
                self?.pause(until: midnight)
            },
            resume: { [weak self] in self?.scheduler.resume(); self?.tick() },
            refresh: { [weak self] in self?.refresh() },
            showDemo: { [weak self] in self?.showDemo() },
            toggleSound: { [weak self] in self?.toggleSound() },
            toggleIncludeUnaccepted: { [weak self] in self?.toggleIncludeUnaccepted() },
            setURL: { [weak self] in self?.showSettings() },
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            quit: { [weak self] in self?.requestQuit() },
            openNotificationSettings: {
                let id = Bundle.main.bundleIdentifier ?? ""
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                    NSWorkspace.shared.open(url)
                }
            }
        ))
        notifier.requestPermission { [weak self] _ in DispatchQueue.main.async { self?.checkNotifications() } }
        if let cached = feed.text { rebuildMeetings(from: cached) }
        icalURL = KeychainStore.read(account: KeychainStore.icalAccount)
        if icalURL == nil {
            showSettings()
        } else {
            refresh()
        }
        // .common mode: keep ticking while the status-bar menu is open (event tracking).
        refreshTimer = Timer(timeInterval: Double(max(1, settings.refreshMinutes)) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        tickTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        for t in [refreshTimer, tickTimer].compactMap({ $0 }) { RunLoop.main.add(t, forMode: .common) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick(); self?.refresh() }
        }
        // Prevent App Nap from coalescing the 30 s tick timer while Gong (an LSUIElement app) is idle in the background.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Gong meeting reminders")
        tick()
    }

    /// Quit, logout or shutdown: put the volume back.
    func willTerminate() { sound.stop() }

    func requestQuit() {
        allowQuit = true
        NSApp.terminate(nil)
    }

    private var failedRefreshes = 0
    private static let quickRetries = 4

    var quitAllowed: Bool { allowQuit || !blocking.isVisible }

    // MARK: - Feed

    func refresh() {
        checkNotifications()
        guard let urlString = icalURL, let url = URL(string: urlString) else {
            updateStatusBar(); return
        }
        guard !isRefreshing else { pendingRefresh = true; return }
        isRefreshing = true
        Task { @MainActor in
            defer {
                isRefreshing = false
                if pendingRefresh {
                    pendingRefresh = false
                    refresh()
                }
            }
            do {
                let text = try await feed.fetch(from: url)
                rebuildMeetings(from: text)
                failedRefreshes = 0
            } catch {
                // Right after wake the network is often not back yet: retry soon, a few times.
                failedRefreshes += 1
                if failedRefreshes <= Self.quickRetries {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.refresh() }
                }
                let summary = (error as? URLError).map { "URLError \($0.code.rawValue)" }
                    ?? (error as? CalendarFeed.FeedError).map { "\($0)" }
                    ?? String(describing: type(of: error))
                NSLog("Feed fetch failed: \(summary)")
            }
            tick()
        }
    }

    private func rebuildMeetings(from text: String) {
        let now = Date()
        // Wide parse window: keep meetings that started up to 24h ago so a snooze made minutes after
        // start still finds its meeting on the next refresh. Scheduler.lateGraceMinutes is the real cutoff.
        let window = ParseWindow(start: now.addingTimeInterval(-24 * 3600),
                                 end: now.addingTimeInterval(48 * 3600))
        let events = ICSParser.parse(text, myEmail: myEmail, window: window)
        meetings = MeetingFilter.meetings(from: events, myEmail: myEmail,
                                          includeUnaccepted: settings.includeUnaccepted)
    }

    // MARK: - Tick

    func tick() {
        let result = scheduler.tick(meetings: meetings)
        for n in result.notifications { notifier.send(meeting: n.meeting, minutesBefore: n.minutesBefore) }
        if result.blocking.isEmpty {
            if blocking.isVisible && !demoActive { blocking.hide() }
        } else {
            if demoActive {   // a real meeting takes over: close the demo first so it gets its own game chance
                demoActive = false
                blocking.hide()
            }
            blocking.show(meetings: result.blocking) { [weak self] meeting, action in self?.handle(action, for: meeting) }
        }
        persistState()
        updateStatusBar()
    }

    private func handle(_ action: BlockingAction, for meeting: Meeting) {
        switch action {
        case .join(let url):
            if VideoLink.isWeb(url) { NSWorkspace.shared.open(url) }   // never smb://, file:// … from an invite
            scheduler.handle(meeting.id)
        case .openCalendar:
            NSWorkspace.shared.open(CalendarLinks.eventURL(calendarEventID: meeting.calendarEventID, email: myEmail))
            scheduler.handle(meeting.id)
        case .snooze:
            scheduler.snooze(meeting.id)
        case .close:
            scheduler.handle(meeting.id)
        }
        // Deferred: this runs from inside the window's own button/Enter action, and tick() can hide() ->
        // teardown() the window that is still dispatching that action.
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }

    private func persistState() {
        try? stateFile.save(PersistedState(states: scheduler.states, pauseUntil: scheduler.pauseUntil))
    }

    // MARK: - Menu actions

    private func pause(until: Date) {
        scheduler.pause(until: until)
        tick()
    }

    /// Changes one setting in memory and in settings.json without overwriting hand edits; a settings.json that
    /// does not decode is left alone (the change then only lives until quit).
    private func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        if let saved = settingsFile.update(default: .default, change) { settings = saved }
    }

    private func toggleSound() {
        let on = !settings.soundEnabled
        updateSettings { $0.soundEnabled = on }
        sound.enabled = settings.soundEnabled
        updateStatusBar()
    }

    private func toggleIncludeUnaccepted() {
        let on = !settings.includeUnaccepted
        updateSettings { $0.includeUnaccepted = on }
        if let cached = feed.text { rebuildMeetings(from: cached) }
        tick()
    }

    /// macOS may need the user's approval (System Settings → Login Items): then that page is opened.
    private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            NSLog("Login item toggle failed: \(error)")
            let alert = NSAlert()
            alert.messageText = L("Could not change Start at login")
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateStatusBar()
    }

    private var notificationsOff = false

    /// Re-checked on every refresh: the user can switch Gong's notifications off in System Settings at any time.
    private func checkNotifications() {
        notifier.isAllowed { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.notificationsOff == allowed else { return }
                self.notificationsOff = !allowed
                self.updateStatusBar()
            }
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                initialURL: icalURL,
                test: { [weak self] urlString in
                    let settings = self?.settings ?? .default
                    guard let url = URL(string: urlString) else { return .failure(URLError(.badURL)) }
                    let probe = CalendarFeed(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent("gong-test.ics"))
                    do {
                        let text = try await probe.fetch(from: url)
                        let now = Date()
                        let me = CalendarIdentity.myEmail(setting: settings.myEmail, icalURL: urlString)
                        let events = ICSParser.parse(text, myEmail: me,
                                                     window: ParseWindow(start: now, end: now.addingTimeInterval(48 * 3600)))
                        return .success(MeetingFilter.meetings(from: events, myEmail: me,
                                                               includeUnaccepted: settings.includeUnaccepted).count)
                    } catch { return .failure(error) }
                },
                save: { [weak self] urlString in
                    do {
                        try KeychainStore.write(urlString, account: KeychainStore.icalAccount)
                        self?.icalURL = urlString
                        Task { @MainActor in self?.refresh() }
                    } catch { NSLog("keychain write failed: \((error as? KeychainStore.KeychainError)?.status ?? -1)") }
                }
            )
        }
        settingsWindow?.show()
    }

    // MARK: - Status bar

    private func updateStatusBar() {
        let hasURL = icalURL != nil
        let dot: StatusBarController.DotColor
        if !hasURL { dot = .red }
        else if scheduler.isPaused { dot = .gray }
        else if feed.isStale(after: Double(settings.staleMinutes) * 60) { dot = .orange }
        else { dot = .green }

        let nextText: String
        if let next = scheduler.nextMeeting(in: meetings) {
            nextText = L("Next: %1$@ at %2$@", next.title, Countdown.timeString(next.start))
        } else {
            nextText = hasURL ? L("No meetings in the next 48 hours") : L("No iCal URL set")
        }
        let refreshed = feed.lastSuccess.map { L("Last refreshed: %@", Countdown.timeString($0)) }
        statusBar.update(dot: dot, model: .init(nextMeetingText: nextText, lastRefreshText: refreshed,
                                                isPaused: scheduler.isPaused, pauseUntil: scheduler.isPaused ? scheduler.pauseUntil : nil,
                                                soundEnabled: settings.soundEnabled,
                                                includeUnaccepted: settings.includeUnaccepted,
                                                launchAtLogin: SMAppService.mainApp.status == .enabled,
                                                loginNeedsApproval: SMAppService.mainApp.status == .requiresApproval,
                                                notificationsOff: notificationsOff,
                                                canShowDemo: !blocking.isVisible || demoActive))
    }

    // MARK: - Debug helpers

    /// `Gong --test-notification`: sends one banner so the notification appearance (icon, sound) can be checked, then quits.
    func runNotificationTest() {
        let meeting = Event(id: "test", uid: "test@gong", title: "Test notification from Gong",
                            start: Date().addingTimeInterval(10 * 60), end: Date().addingTimeInterval(40 * 60),
                            isAllDay: false, attendees: [], myStatus: .accepted, meetURL: nil, description: nil, location: nil)
        notifier.requestPermission { [notifier] granted in
            DispatchQueue.main.async {
                if granted { notifier.send(meeting: meeting, minutesBefore: 10) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: - Demo

    /// Menu "Show demo modal": the real modal with a sample meeting, to try it out. Every button just closes it;
    /// nothing is opened and the scheduler's state is untouched. A fresh id per demo gives a new game chance.
    func showDemo() {
        guard !blocking.isVisible else { return }
        demoActive = true
        blocking.show(meetings: demoMeetings(id: "demo-\(UUID().uuidString)")) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.demoActive else { return }
                self.demoActive = false
                self.blocking.hide()
                self.updateStatusBar()
            }
        }
        updateStatusBar()
    }

    func runDemo() {
        blocking.show(meetings: demoMeetings()) { [weak self] meeting, action in
            NSLog("demo action: \(action) for \(meeting.title)")
            DispatchQueue.main.async { [weak self] in
                self?.blocking.hide()
                NSApp.terminate(nil)
            }
        }
    }

    /// `Gong --snapshot <file.png> [seconds-into-cycle] [--multi | --secondary | --gameover]`: renders the modal offscreen to a PNG
    /// (no window, no sound, no screen-recording permission needed), then quits.
    func runSnapshot(to path: String, cycleTime: Double) {
        // `--game`: the ninja arena alone (no window, no sound).
        if CommandLine.arguments.contains("--game") {
            var g = NinjaGame(seed: 1)
            for _ in 0..<Int(max(1, cycleTime) * 60) { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 2) }
            let canvas = GameRenderer().render(g, time: g.runTime).scaled(to: NinjaGame.width * 4)
            if let image = canvas.cgImage() {
                let rep = NSBitmapImageRep(cgImage: image)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
            }
            NSApp.terminate(nil); return
        }
        let clock = StrikeClock(start: Date().addingTimeInterval(-cycleTime))
        // Panels are fixed-size; render just around them.
        let size = CGSize(width: RetroTheme.panelWidth + 80, height: RetroTheme.primaryHeight + RetroTheme.gameButtonsHeight + RetroTheme.rowHeight + 120)
        // `--secondary`: the panel shown on the other screens instead of the modal.
        let game = GameController(sound: GongSoundPlayer(enabled: false), best: 0, clock: clock, saveBest: { _ in })
        // `--gameover`: the modal right after a lost game, with the meeting buttons over the world.
        if CommandLine.arguments.contains("--gameover") { game.snapshotGameOver() }
        let content: AnyView = CommandLine.arguments.contains("--secondary")
            ? AnyView(SecondaryScreenView(start: demoMeetings()[0].start))
            : AnyView(BlockingView(meetings: demoMeetings(), game: game) { _, _ in })
        let view = content
            .frame(width: size.width, height: size.height)
            .background(Color.black.opacity(RetroTheme.screenDim))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { NSLog("snapshot write failed: \(error)") }
        } else {
            NSLog("snapshot render failed")
        }
        NSApp.terminate(nil)
    }

    private func demoMeetings(id: String = "demo") -> [Meeting] {
        let start = Date().addingTimeInterval(4 * 60)
        let demoMeeting = Event(
            id: id, uid: "demo@example.com", title: "Sprint Refinement — Mobile App",
            start: start, end: start.addingTimeInterval(3600), isAllDay: false,
            attendees: [Attendee(email: "alex@example.com", name: "Alex Example", status: .accepted),
                        Attendee(email: myEmail.isEmpty ? "you@example.com" : myEmail, name: "You", status: .accepted)],
            myStatus: .accepted, meetURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            description: "Going through the open items from the last sprint.\nSecond line.", location: nil)
        var demoMeetings = [demoMeeting]
        // `--demo --multi`: an overlapping second meeting, shown as a compact row
        if CommandLine.arguments.contains("--multi") {
            demoMeetings.append(Event(
                id: "demo2", uid: "demo2@example.com", title: "1:1 Anne — quarterly planning and the Q1 roadmap",
                start: start.addingTimeInterval(60), end: start.addingTimeInterval(1800), isAllDay: false,
                attendees: [], myStatus: .accepted, meetURL: nil, description: nil, location: nil))
        }
        return demoMeetings
    }
}
