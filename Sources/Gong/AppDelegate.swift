import AppKit
import GongCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let demo: Bool
    let testNotification: Bool
    private var coordinator: AppCoordinator!

    init(demo: Bool, testNotification: Bool = false) {
        self.demo = demo
        self.testNotification = testNotification
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let t = i + 2 < args.count ? Double(args[i + 2]) ?? 5 : 5
            coordinator.runSnapshot(to: args[i + 1], cycleTime: t)
        } else if demo {
            coordinator.runDemo()
        } else if testNotification {
            coordinator.runNotificationTest()
        } else {
            coordinator.start()
        }
    }

    /// The modal can't be quit away from Gong's own menu, but logout, restart and shutdown always go through.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let systemQuit = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: kAEQuitReason) != nil
        return systemQuit || coordinator.quitAllowed ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.willTerminate()
    }
}
