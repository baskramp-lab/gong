import XCTest
@testable import GongCore

final class CalendarLinksTests: XCTestCase {
    func testEventURL() {
        let url = CalendarLinks.eventURL(calendarEventID: "abc123", email: "alex@example.com")
        XCTAssertEqual(url.absoluteString, "https://calendar.google.com/calendar/event?eid=YWJjMTIzIGFsZXhAZXhhbXBsZS5jb20")
    }

    func testDayURL() {
        let url = CalendarLinks.dayURL(for: utc("2026-09-28T12:00:00Z"), timeZone: amsterdam)
        XCTAssertEqual(url.absoluteString, "https://calendar.google.com/calendar/r/day/2026/9/28")
    }
}
