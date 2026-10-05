import XCTest
@testable import GongCore

final class ICSDateTests: XCTestCase {
    func testUTC() {
        let p = ICSDate.parse("20260928T120000Z", tzid: nil, isDateValue: false, defaultTZ: amsterdam)!
        XCTAssertEqual(p.date, utc("2026-09-28T12:00:00Z"))
        XCTAssertFalse(p.isDateOnly)
        XCTAssertEqual(p.timeZone.secondsFromGMT(for: p.date), 0)
    }

    func testTZIDSummerTime() {
        let p = ICSDate.parse("20260928T140000", tzid: "Europe/Amsterdam", isDateValue: false, defaultTZ: .init(identifier: "UTC")!)!
        XCTAssertEqual(p.date, utc("2026-09-28T12:00:00Z"))
        XCTAssertEqual(p.timeZone, amsterdam)
    }

    func testTZIDWinterTime() {
        let p = ICSDate.parse("20261215T140000", tzid: "Europe/Amsterdam", isDateValue: false, defaultTZ: .init(identifier: "UTC")!)!
        XCTAssertEqual(p.date, utc("2026-12-15T13:00:00Z"))
    }

    func testDateOnly() {
        let p = ICSDate.parse("20260928", tzid: nil, isDateValue: true, defaultTZ: amsterdam)!
        XCTAssertTrue(p.isDateOnly)
        XCTAssertEqual(p.date, utc("2026-09-27T22:00:00Z")) // midnight Amsterdam
    }

    func testEightDigitsWithoutValueParamIsDateOnly() {
        XCTAssertTrue(ICSDate.parse("20260928", tzid: nil, isDateValue: false, defaultTZ: amsterdam)!.isDateOnly)
    }

    func testFloatingUsesDefaultTZ() {
        let p = ICSDate.parse("20260928T140000", tzid: nil, isDateValue: false, defaultTZ: amsterdam)!
        XCTAssertEqual(p.date, utc("2026-09-28T12:00:00Z"))
    }

    func testUnknownTZIDFallsBackToDefault() {
        let p = ICSDate.parse("20260928T140000", tzid: "Mars/Olympus", isDateValue: false, defaultTZ: amsterdam)!
        XCTAssertEqual(p.date, utc("2026-09-28T12:00:00Z"))
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ICSDate.parse("banana", tzid: nil, isDateValue: false, defaultTZ: amsterdam))
    }
}
