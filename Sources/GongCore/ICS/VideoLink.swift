import Foundation

public enum VideoLink {
    /// Preferred order: Meet first, then other video hosts.
    static let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.cloud.microsoft", "teams.live.com"]

    /// Only web links are opened: a calendar invite from anyone can put `smb://`, `file://` or custom-scheme
    /// links in its location or description.
    public static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// `host` itself or a real subdomain of it (`us02web.zoom.us`), never a look-alike (`evilzoom.us`).
    static func matches(_ url: URL, host: String) -> Bool {
        let h = (url.host ?? "").lowercased()
        return h == host || h.hasSuffix("." + host)
    }

    static func find(conference: String?, description: String?, location: String?) -> URL? {
        if let c = conference?.trimmingCharacters(in: .whitespacesAndNewlines),
           let u = URL(string: c), isWeb(u) {
            return u
        }
        var found: [URL] = []
        for text in [location, description].compactMap({ $0 }) {
            found += urls(in: text).filter(isWeb)
        }
        for host in hosts {
            if let u = found.first(where: { matches($0, host: host) }) { return u }
        }
        return nil
    }

    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}
