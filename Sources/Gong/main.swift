import AppKit
import GongCore

let app = NSApplication.shared
let delegate = AppDelegate(demo: CommandLine.arguments.contains("--demo"),
                           testNotification: CommandLine.arguments.contains("--test-notification"))
app.delegate = delegate
app.setActivationPolicy(.accessory)

// An accessory app has no visible main menu, but AppKit still routes ⌘X/⌘C/⌘V/⌘A
// through it. Without an Edit menu, pasting into the settings window's text field
// does not work.
let mainMenu = NSMenu()
let editItem = NSMenuItem()
let editMenu = NSMenu(title: L("Edit"))
editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu
mainMenu.addItem(editItem)
app.mainMenu = mainMenu

app.run()
