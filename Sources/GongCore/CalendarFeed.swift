import Foundation

/// Fetches the iCal feed, keeps the last good copy on disk, and knows whether that copy is stale.
@MainActor
public final class CalendarFeed {
    public enum FeedError: LocalizedError, Equatable {
        case badStatus(Int)
        case notACalendar
        /// HTTP 429: the server wants fewer requests. No new request goes out before `until`.
        case rateLimited(until: Date)

        public var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                return L("The server answered with status %d. Check that the URL is still valid (Google may have reset the secret address).", code)
            case .notACalendar:
                return L("This address is not a calendar (no VCALENDAR). Paste the \"Secret address in iCal format\", not the regular calendar link.")
            case .rateLimited(let until):
                return L("Google is limiting requests. Next try at %@.", Countdown.timeString(until))
            }
        }
    }

    private let cacheURL: URL
    private let session: URLSession
    private let now: () -> Date

    public private(set) var text: String?
    public private(set) var lastSuccess: Date?
    /// Set after an HTTP 429: `fetch` sends nothing before this time. Cleared by the next successful fetch.
    public private(set) var retryNotBefore: Date?
    private var rateLimitHits = 0

    /// Backoff after consecutive 429s: 5, 10, 20, 40, then 60 minutes; a longer Retry-After from the server wins.
    public static func backoff(hits: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let minutes = min(60, 5 * (1 << min(max(hits - 1, 0), 4)))
        return max(Double(minutes) * 60, retryAfter ?? 0)
    }

    /// Retry-After is either delta-seconds or an HTTP date.
    public static func parseRetryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if let seconds = TimeInterval(v) { return max(0, seconds) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: v).map { max(0, $0.timeIntervalSince(now)) }
    }

    /// True while a 429 backoff is running (the menu shows when the next try is).
    public var isRateLimited: Bool { retryNotBefore.map { now() < $0 } ?? false }

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
        if let until = retryNotBefore, now() < until { throw FeedError.rateLimited(until: until) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        if status == 429 {
            rateLimitHits += 1
            let retryAfter = Self.parseRetryAfter(http?.value(forHTTPHeaderField: "Retry-After"), now: now())
            let until = now().addingTimeInterval(Self.backoff(hits: rateLimitHits, retryAfter: retryAfter))
            retryNotBefore = until
            throw FeedError.rateLimited(until: until)
        }
        guard (200..<300).contains(status) else { throw FeedError.badStatus(status) }
        let s = ContentLine.decode(data)
        guard s.contains("BEGIN:VCALENDAR") else { throw FeedError.notACalendar }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        text = s
        lastSuccess = now()
        rateLimitHits = 0
        retryNotBefore = nil
        return s
    }
}
