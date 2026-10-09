import XCTest
@testable import GongCore

@MainActor
final class CalendarFeedTests: XCTestCase {
    func tempCache() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gong-feed-\(UUID().uuidString)/last-feed.ics")
    }

    func testLoadsCacheAtInit() throws {
        let url = tempCache()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("BEGIN:VCALENDAR\nEND:VCALENDAR".utf8).write(to: url)
        let feed = CalendarFeed(cacheURL: url, now: { utc("2026-09-28T12:00:00Z") })
        XCTAssertEqual(feed.text, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertNotNil(feed.lastSuccess)
    }

    func testNoCacheMeansStale() {
        let feed = CalendarFeed(cacheURL: tempCache(), now: { utc("2026-09-28T12:00:00Z") })
        XCTAssertNil(feed.text)
        XCTAssertTrue(feed.isStale(after: 15 * 60))
    }

    func testStaleAfterInterval() throws {
        let url = tempCache()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("BEGIN:VCALENDAR\nEND:VCALENDAR".utf8).write(to: url)
        var now = Date()
        let feed = CalendarFeed(cacheURL: url, now: { now })
        XCTAssertFalse(feed.isStale(after: 15 * 60))
        now = now.addingTimeInterval(16 * 60)
        XCTAssertTrue(feed.isStale(after: 15 * 60))
    }

    func testFetchRejectsNonCalendarBody() async throws {
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 200, body: "<html>login</html>"), now: Date.init)
        do {
            _ = try await feed.fetch(from: URL(string: "https://example.com/basic.ics")!)
            XCTFail("expected error")
        } catch let e as CalendarFeed.FeedError {
            XCTAssertEqual(e, .notACalendar)
        }
    }

    func testFetchStoresCacheAndText() async throws {
        let url = tempCache()
        let feed = CalendarFeed(cacheURL: url, session: StubSession.make(status: 200, body: "BEGIN:VCALENDAR\nEND:VCALENDAR"), now: Date.init)
        let text = try await feed.fetch(from: URL(string: "https://example.com/basic.ics")!)
        XCTAssertEqual(text, "BEGIN:VCALENDAR\nEND:VCALENDAR")
        XCTAssertEqual(feed.text, text)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
    }

    func testFetchBadStatus() async {
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 404, body: ""), now: Date.init)
        do {
            _ = try await feed.fetch(from: URL(string: "https://example.com/basic.ics")!)
            XCTFail("expected error")
        } catch let e as CalendarFeed.FeedError {
            XCTAssertEqual(e, .badStatus(404))
        } catch { XCTFail("wrong error \(error)") }
    }

    func testFetchDecodesCharacterSplitAcrossFold() async throws {
        let body = Data("BEGIN:VCALENDAR\r\nSUMMARY:".utf8) + Data([0x41, 0xC3, 0x0D, 0x0A, 0x20, 0xA9]) + Data("\r\nEND:VCALENDAR\r\n".utf8)
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 200, data: body), now: Date.init)
        let text = try await feed.fetch(from: URL(string: "https://example.com/basic.ics")!)
        XCTAssertTrue(text.contains("SUMMARY:A\u{E9}"))
    }

    func testFetchAcceptsInvalidUTF8Lossily() async throws {
        let body = Data("BEGIN:VCALENDAR\nSUMMARY:A".utf8) + Data([0xFF]) + Data("\nEND:VCALENDAR".utf8)
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 200, data: body), now: Date.init)
        let text = try await feed.fetch(from: URL(string: "https://example.com/basic.ics")!)
        XCTAssertTrue(text.contains("SUMMARY:A\u{FFFD}"))
    }

    func testFetchStillRequiresVCalendarAfterLossyDecode() async {
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 200, data: Data([0xFF, 0x41])), now: Date.init)
        do {
            _ = try await feed.fetch(from: URL(string: "https://example.com/basic.ics")!)
            XCTFail("expected error")
        } catch let e as CalendarFeed.FeedError {
            XCTAssertEqual(e, .notACalendar)
        } catch { XCTFail("wrong error \(error)") }
    }

    func testFeedErrorsHaveReadableDescriptions() {
        XCTAssertTrue(CalendarFeed.FeedError.badStatus(404).localizedDescription.contains("404"))
        XCTAssertTrue(CalendarFeed.FeedError.notACalendar.localizedDescription.contains("VCALENDAR"))
    }

    // MARK: - 429 backoff

    let feedURL = URL(string: "https://example.com/basic.ics")!

    func testBackoffDoublesUpToAnHour() {
        XCTAssertEqual([1, 2, 3, 4, 5, 9].map { CalendarFeed.backoff(hits: $0, retryAfter: nil) / 60 }, [5, 10, 20, 40, 60, 60])
        XCTAssertEqual(CalendarFeed.backoff(hits: 1, retryAfter: 7200), 7200)
        XCTAssertEqual(CalendarFeed.backoff(hits: 3, retryAfter: 30), 20 * 60)
    }

    func testParsesRetryAfterSecondsAndDate() {
        let now = utc("2026-10-09T09:00:00Z")
        XCTAssertEqual(CalendarFeed.parseRetryAfter("120", now: now), 120)
        XCTAssertEqual(CalendarFeed.parseRetryAfter("Fri, 09 Oct 2026 09:30:00 GMT", now: now), 1800)
        XCTAssertNil(CalendarFeed.parseRetryAfter("soon", now: now))
        XCTAssertNil(CalendarFeed.parseRetryAfter(nil, now: now))
    }

    func testRateLimitBlocksRequestsUntilBackoffEnds() async throws {
        var now = utc("2026-10-09T09:00:00Z")
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 429, body: "", headers: ["Retry-After": "600"]),
                                now: { now })
        do { _ = try await feed.fetch(from: feedURL); XCTFail("expected error") }
        catch let e as CalendarFeed.FeedError { XCTAssertEqual(e, .rateLimited(until: utc("2026-10-09T09:10:00Z"))) }
        XCTAssertTrue(feed.isRateLimited)
        XCTAssertEqual(StubProtocol.requests, 1)

        now = utc("2026-10-09T09:05:00Z")   // still inside the backoff: no request goes out
        do { _ = try await feed.fetch(from: feedURL); XCTFail("expected error") }
        catch let e as CalendarFeed.FeedError { XCTAssertEqual(e, .rateLimited(until: utc("2026-10-09T09:10:00Z"))) }
        XCTAssertEqual(StubProtocol.requests, 1)

        now = utc("2026-10-09T09:11:00Z")   // second 429 in a row: 10 minutes beats the 600 s Retry-After
        do { _ = try await feed.fetch(from: feedURL); XCTFail("expected error") }
        catch let e as CalendarFeed.FeedError { XCTAssertEqual(e, .rateLimited(until: utc("2026-10-09T09:21:00Z"))) }
        XCTAssertEqual(StubProtocol.requests, 2)
    }

    func testSuccessClearsRateLimit() async throws {
        var now = utc("2026-10-09T09:00:00Z")
        let feed = CalendarFeed(cacheURL: tempCache(), session: StubSession.make(status: 429, body: ""), now: { now })
        _ = try? await feed.fetch(from: feedURL)
        XCTAssertEqual(feed.retryNotBefore, utc("2026-10-09T09:05:00Z"))
        now = utc("2026-10-09T09:06:00Z")
        StubProtocol.status = 200
        StubProtocol.body = Data("BEGIN:VCALENDAR\nEND:VCALENDAR".utf8)
        _ = try await feed.fetch(from: feedURL)
        XCTAssertNil(feed.retryNotBefore)
        XCTAssertFalse(feed.isRateLimited)
    }

    func testStaleThresholdIsAtLeastTwoRefreshPeriods() {
        var s = AppSettings()
        XCTAssertEqual(s.staleThreshold, 35 * 60)
        s.refreshMinutes = 30; s.staleMinutes = 15
        XCTAssertEqual(s.staleThreshold, 65 * 60)
    }
}

/// URLProtocol stub so CalendarFeed can be tested without network.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum StubSession {
    static func make(status: Int, body: String, headers: [String: String] = [:]) -> URLSession {
        make(status: status, data: Data(body.utf8), headers: headers)
    }

    static func make(status: Int, data: Data, headers: [String: String] = [:]) -> URLSession {
        StubProtocol.status = status
        StubProtocol.body = data
        StubProtocol.headers = headers
        StubProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
}
