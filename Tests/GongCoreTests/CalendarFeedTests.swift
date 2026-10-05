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
}

/// URLProtocol stub so CalendarFeed can be tested without network.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum StubSession {
    static func make(status: Int, body: String) -> URLSession {
        make(status: status, data: Data(body.utf8))
    }

    static func make(status: Int, data: Data) -> URLSession {
        StubProtocol.status = status
        StubProtocol.body = data
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }
}
