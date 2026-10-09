import AppKit
import GongCore

final class StatusBarController {
    enum DotColor { case green, gray, orange, red }

    struct MenuModel {
        var nextMeetingText: String
        var lastRefreshText: String?
        /// Google answered 429; when Gong will try again. Nil when not rate limited.
        var rateLimitText: String?
        var isPaused: Bool
        var pauseUntil: Date?
        var soundEnabled: Bool
        var includeUnaccepted: Bool
        var launchAtLogin: Bool
        /// The login item is registered but waits for the user's approval in System Settings.
        var loginNeedsApproval: Bool
        /// macOS does not allow Gong's notifications (soft reminders won't show).
        var notificationsOff: Bool
        /// False while a real meeting's modal is up.
        var canShowDemo: Bool
        /// A newer release on GitHub (its version), or nil.
        var updateVersion: String?
    }

    struct Actions {
        var pauseMinutes: (Int) -> Void
        var pauseToday: () -> Void
        var resume: () -> Void
        var refresh: () -> Void
        var showDemo: () -> Void
        var toggleSound: () -> Void
        var toggleIncludeUnaccepted: () -> Void
        var setURL: () -> Void
        var toggleLaunchAtLogin: () -> Void
        var quit: () -> Void
        var openNotificationSettings: () -> Void
        var openUpdatePage: () -> Void
        var copyUpdateCommand: () -> Void
    }

    private let item: NSStatusItem
    private let actions: Actions
    private let menu = NSMenu()

    private let nextItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let refreshedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let rateLimitItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(openUpdatePage), keyEquivalent: "")
    private let copyUpdateItem = NSMenuItem(title: L("Copy update command"), action: #selector(copyUpdateCommand), keyEquivalent: "")
    private let updateSeparator = NSMenuItem.separator()
    private let notificationsItem = NSMenuItem(title: L("⚠︎ Notifications are off — Open Settings…"), action: #selector(openNotificationSettings), keyEquivalent: "")
    static let pauseOptions: [(title: String, minutes: Int)] = [
        (L("15 minutes"), 15), (L("30 minutes"), 30), (L("1 hour"), 60), (L("2 hours"), 120), (L("4 hours"), 240),
    ]
    private let pauseItem = NSMenuItem(title: L("Pause"), action: nil, keyEquivalent: "")
    private let pauseTodayItem = NSMenuItem(title: L("Rest of the day"), action: #selector(pauseToday), keyEquivalent: "")
    private let resumeItem = NSMenuItem(title: L("Resume"), action: #selector(resume), keyEquivalent: "")
    private let demoItem = NSMenuItem(title: L("Show demo modal"), action: #selector(showDemo), keyEquivalent: "d")
    private let refreshItem = NSMenuItem(title: L("Refresh now"), action: #selector(refresh), keyEquivalent: "r")
    private let soundItem = NSMenuItem(title: L("Sound on"), action: #selector(toggleSound), keyEquivalent: "")
    private let unacceptedItem = NSMenuItem(title: L("Include unaccepted meetings"), action: #selector(toggleUnaccepted), keyEquivalent: "")
    private let urlItem = NSMenuItem(title: L("Set iCal URL…"), action: #selector(setURL), keyEquivalent: ",")
    private let loginItem = NSMenuItem(title: L("Start at login"), action: #selector(toggleLogin), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: L("Quit"), action: #selector(quit), keyEquivalent: "q")

    /// Small coloured dot in the top-right corner of the menu bar button (error / stale feed / update available).
    private final class BadgeView: NSView {
        var color: NSColor = .systemRed { didSet { needsDisplay = true } }
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }
    private let badge = BadgeView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))

    init(actions: Actions) {
        self.actions = actions
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.gongImage()
        badge.isHidden = true
        item.button?.addSubview(badge)
        for mi in [nextItem, refreshedItem, rateLimitItem] { mi.isEnabled = false }
        for mi in [updateItem, copyUpdateItem, notificationsItem, pauseTodayItem, resumeItem, demoItem, refreshItem, soundItem, unacceptedItem, urlItem, loginItem, quitItem] { mi.target = self }
        let pauseMenu = NSMenu(title: L("Pause"))
        pauseMenu.autoenablesItems = false
        for option in Self.pauseOptions {
            let mi = NSMenuItem(title: option.title, action: #selector(pauseMinutes(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = option.minutes
            pauseMenu.addItem(mi)
        }
        pauseMenu.addItem(.separator())
        pauseMenu.addItem(pauseTodayItem)
        pauseItem.submenu = pauseMenu
        menu.autoenablesItems = false
        menu.items = [updateItem, copyUpdateItem, updateSeparator, nextItem, refreshedItem, rateLimitItem, notificationsItem, .separator(), pauseItem, resumeItem, .separator(),
                      demoItem, refreshItem, soundItem, unacceptedItem, .separator(), urlItem, loginItem, .separator(), quitItem]
        item.menu = menu
        item.button?.toolTip = "Gong"
    }

    func update(dot: DotColor, model: MenuModel) {
        if let button = item.button {
            button.appearsDisabled = (dot == .gray)
            // A problem (red, orange) outranks an available update (blue).
            let color: NSColor?
            switch dot {
            case .red: color = .systemRed
            case .orange: color = .systemOrange
            case .green, .gray: color = model.updateVersion == nil ? nil : .systemBlue
            }
            if let color {
                badge.color = color
                badge.frame = NSRect(x: button.bounds.maxX - badge.bounds.width - 2,
                                     y: button.bounds.maxY - badge.bounds.height - 2,
                                     width: badge.bounds.width, height: badge.bounds.height)
            }
            badge.isHidden = color == nil
            button.toolTip = model.updateVersion.map { L("Gong — update available: %@", $0) } ?? "Gong"
        }
        updateItem.title = model.updateVersion.map { L("Update available: %@…", $0) } ?? ""
        for mi in [updateItem, copyUpdateItem, updateSeparator] { mi.isHidden = model.updateVersion == nil }
        nextItem.title = model.nextMeetingText
        refreshedItem.title = model.lastRefreshText ?? L("Not refreshed yet")
        refreshedItem.isHidden = false
        rateLimitItem.title = model.rateLimitText ?? ""
        rateLimitItem.isHidden = model.rateLimitText == nil
        pauseItem.isHidden = model.isPaused
        resumeItem.isHidden = !model.isPaused
        if let until = model.pauseUntil {
            resumeItem.title = L("Resume (paused until %@)", Countdown.timeString(until))
        } else {
            resumeItem.title = L("Resume")
        }
        soundItem.state = model.soundEnabled ? .on : .off
        unacceptedItem.state = model.includeUnaccepted ? .on : .off
        loginItem.state = model.launchAtLogin ? .on : model.loginNeedsApproval ? .mixed : .off
        notificationsItem.isHidden = !model.notificationsOff
        demoItem.isEnabled = model.canShowDemo
    }

    /// A small gong on its stand as a template image: macOS renders it white/black like the other menu bar icons
    /// and dims it when `appearsDisabled` is set (18×18 pt, drawn in points so it stays crisp on Retina).
    static func gongImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            // stand: top beam + two posts
            NSBezierPath(roundedRect: NSRect(x: 0.5, y: 15, width: 17, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1, width: 1.6, height: 14.5), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 14.9, y: 1, width: 1.6, height: 14.5), xRadius: 0.8, yRadius: 0.8).fill()
            // ropes
            NSBezierPath(rect: NSRect(x: 6.2, y: 12, width: 0.9, height: 3.2)).fill()
            NSBezierPath(rect: NSRect(x: 10.9, y: 12, width: 0.9, height: 3.2)).fill()
            // disc with the boss cut out (even-odd)
            let disc = NSBezierPath(ovalIn: NSRect(x: 3.8, y: 1.5, width: 10.4, height: 10.4))
            disc.append(NSBezierPath(ovalIn: NSRect(x: 7.5, y: 5.2, width: 3, height: 3)))
            disc.windingRule = .evenOdd
            disc.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func pauseMinutes(_ sender: NSMenuItem) { actions.pauseMinutes(sender.tag) }
    @objc private func pauseToday() { actions.pauseToday() }
    @objc private func resume() { actions.resume() }
    @objc private func showDemo() { actions.showDemo() }
    @objc private func refresh() { actions.refresh() }
    @objc private func toggleSound() { actions.toggleSound() }
    @objc private func toggleUnaccepted() { actions.toggleIncludeUnaccepted() }
    @objc private func setURL() { actions.setURL() }
    @objc private func toggleLogin() { actions.toggleLaunchAtLogin() }
    @objc private func quit() { actions.quit() }
    @objc private func openNotificationSettings() { actions.openNotificationSettings() }
    @objc private func openUpdatePage() { actions.openUpdatePage() }
    @objc private func copyUpdateCommand() { actions.copyUpdateCommand() }
}
