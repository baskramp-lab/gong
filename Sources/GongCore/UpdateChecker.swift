import Foundation

/// A dotted numeric version ("1.2.3", tags may start with "v"); missing parts count as 0, so 1.0 == 1.0.0.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(to count: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, count - parts.count)) }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(to: n) == b.padded(to: n)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(to: n).lexicographicallyPrecedes(b.padded(to: n))
    }
}

/// Asks GitHub for the latest release (at most once a day) and remembers whether it is newer than this build.
/// Any failure (offline, rate limit, odd tag) is silent and leaves the result unchanged.
@MainActor
public final class UpdateChecker {
    public struct Release: Equatable {
        public let version: String
        public let pageURL: URL
    }

    public static let defaultAPIURL = URL(string: "https://api.github.com/repos/baskramp-lab/gong/releases/latest")!
    public static let interval: TimeInterval = 24 * 3600

    private let current: AppVersion?
    private let apiURL: URL
    private let session: URLSession
    private let now: () -> Date

    public private(set) var available: Release?
    public var lastCheck: Date?
    public var isDue: Bool { lastCheck.map { now().timeIntervalSince($0) >= Self.interval } ?? true }

    public init(currentVersion: String, apiURL: URL = defaultAPIURL, session: URLSession = .shared,
                now: @escaping () -> Date = Date.init) {
        current = AppVersion(currentVersion)
        self.apiURL = apiURL
        self.session = session
        self.now = now
    }

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: URL
    }

    public func check() async {
        lastCheck = now()
        guard let current else { return }
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let latest = AppVersion(payload.tag_name) else { return }
        available = current < latest ? Release(version: latest.description, pageURL: payload.html_url) : nil
    }

    /// The Terminal command that updates a self-built copy; `sourcePath` is the cloned folder the app was built from.
    public static func updateCommand(sourcePath: String?) -> String {
        let update = "git pull && scripts/build-app.sh --install && open /Applications/Gong.app"
        guard let path = sourcePath, !path.isEmpty else { return update }
        return "cd '\(path.replacingOccurrences(of: "'", with: #"'\''"#))' && " + update
    }
}
