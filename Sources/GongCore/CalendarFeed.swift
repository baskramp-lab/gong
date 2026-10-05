import Foundation

/// Fetches the iCal feed, keeps the last good copy on disk, and knows whether that copy is stale.
@MainActor
public final class CalendarFeed {
    public enum FeedError: LocalizedError, Equatable {
        case badStatus(Int)
        case notACalendar

        public var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                return L("The server answered with status %d. Check that the URL is still valid (Google may have reset the secret address).", code)
            case .notACalendar:
                return L("This address is not a calendar (no VCALENDAR). Paste the \"Secret address in iCal format\", not the regular calendar link.")
            }
        }
    }

    private let cacheURL: URL
    private let session: URLSession
    private let now: () -> Date

    public private(set) var text: String?
    public private(set) var lastSuccess: Date?

    public init(cacheURL: URL, session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.cacheURL = cacheURL
        self.session = session
        self.now = now
        if let data = try? Data(contentsOf: cacheURL) {
            text = ContentLine.decode(data)
            let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
            lastSuccess = attrs?[.modificationDate] as? Date
        }
    }

    public func isStale(after interval: TimeInterval) -> Bool {
        guard let last = lastSuccess else { return true }
        return now().timeIntervalSince(last) > interval
    }

    @discardableResult
    public func fetch(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw FeedError.badStatus(status) }
        let s = ContentLine.decode(data)
        guard s.contains("BEGIN:VCALENDAR") else { throw FeedError.notACalendar }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        text = s
        lastSuccess = now()
        return s
    }
}
