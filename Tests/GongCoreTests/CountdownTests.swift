import XCTest
@testable import GongCore

final class CountdownTests: XCTestCase {
    let start = utc("2026-09-28T12:00:00Z") // 14:00 Amsterdam

    func testMinutesBefore() {
        XCTAssertEqual(Countdown.text(start: start, now: start.addingTimeInterval(-4 * 60 - 20), timeZone: amsterdam),
                       "starts at 14:00 — in 4 min")
    }

    func testUnderOneMinute() {
        XCTAssertEqual(Countdown.text(start: start, now: start.addingTimeInterval(-30), timeZone: amsterdam),
                       "starts at 14:00 — in less than 1 min")
    }

    func testExactlyNow() {
        XCTAssertEqual(Countdown.text(start: start, now: start, timeZone: amsterdam), "starting now — 14:00")
    }

    func testAfterStart() {
        XCTAssertEqual(Countdown.text(start: start, now: start.addingTimeInterval(2 * 60 + 5), timeZone: amsterdam),
                       "started 2 min ago — 14:00")
    }
}
