import Foundation

public enum AppPaths {
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gong", isDirectory: true)
    }
    public static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    public static var stateFile: URL { supportDirectory.appendingPathComponent("state.json") }
    public static var feedCacheFile: URL { supportDirectory.appendingPathComponent("last-feed.ics") }
}
