import AppKit
import SwiftUI
import GongCore

final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsViewModel

    init(initialURL: String?, test: @escaping (String) async -> Result<Int, Error>, save: @escaping (String) -> Void) {
        model = SettingsViewModel(initialURL: initialURL, test: test, save: save)
        model.onSaved = { [weak self] in self?.close() }   // saved: done, the window can go
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L("Gong — iCal URL")
            w.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
