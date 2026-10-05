import XCTest
@testable import GongCore

final class RecurrenceRuleTests: XCTestCase {
    let utcTZ = TimeZone(identifier: "UTC")!
    let farStart = utc("2020-01-01T00:00:00Z")
    let farEnd = utc("2030-01-01T00:00:00Z")

    func occ(_ rule: String, dtstart: Date, tz: TimeZone? = nil, from: Date? = nil, to: Date? = nil) -> [Date] {
        let r = RecurrenceRule.parse(rule, defaultTZ: tz ?? utcTZ)!
        return r.occurrences(from: dtstart, timeZone: tz ?? utcTZ, windowStart: from ?? farStart, windowEnd: to ?? farEnd)
    }

    func testUnsupportedFrequencyIsNil() {
        XCTAssertNil(RecurrenceRule.parse("FREQ=HOURLY", defaultTZ: utcTZ))
        XCTAssertNil(RecurrenceRule.parse("INTERVAL=2", defaultTZ: utcTZ))
    }

    func testDailyIntervalCount() {
        let dates = occ("FREQ=DAILY;INTERVAL=2;COUNT=3", dtstart: utc("2026-09-28T12:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-28T12:00:00Z"), utc("2026-09-30T12:00:00Z"), utc("2026-10-02T12:00:00Z")])
    }

    func testWeeklyByDay() {
        // 2026-09-28 is a Monday
        let dates = occ("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3", dtstart: utc("2026-09-28T12:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-28T12:00:00Z"), utc("2026-09-30T12:00:00Z"), utc("2026-10-05T12:00:00Z")])
    }

    func testWeeklyWithoutByDayUsesStartWeekday() {
        let dates = occ("FREQ=WEEKLY;INTERVAL=2;COUNT=2", dtstart: utc("2026-09-30T12:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-30T12:00:00Z"), utc("2026-10-14T12:00:00Z")])
    }

    func testUntilInclusive() {
        let dates = occ("FREQ=WEEKLY;BYDAY=MO;UNTIL=20261005T120000Z", dtstart: utc("2026-09-28T12:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-28T12:00:00Z"), utc("2026-10-05T12:00:00Z")])
    }

    func testUntilDateOnlyCoversWholeDay() {
        let dates = occ("FREQ=DAILY;UNTIL=20260929", dtstart: utc("2026-09-28T12:00:00Z"))
        XCTAssertEqual(dates.count, 2)
    }

    func testMonthlySecondTuesday() {
        // 2026-10-13 and 2026-11-10 are second Tuesdays
        let dates = occ("FREQ=MONTHLY;BYDAY=2TU;COUNT=2", dtstart: utc("2026-10-13T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-13T10:00:00Z"), utc("2026-11-10T10:00:00Z")])
    }

    func testMonthlyLastFriday() {
        // last Fridays: 2026-10-30, 2026-11-27
        let dates = occ("FREQ=MONTHLY;BYDAY=-1FR;COUNT=2", dtstart: utc("2026-10-30T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-30T10:00:00Z"), utc("2026-11-27T10:00:00Z")])
    }

    func testMonthlyByMonthDay() {
        let dates = occ("FREQ=MONTHLY;BYMONTHDAY=15;COUNT=2", dtstart: utc("2026-10-15T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-15T10:00:00Z"), utc("2026-11-15T10:00:00Z")])
    }

    func testMonthlySameDayFallback() {
        let dates = occ("FREQ=MONTHLY;COUNT=2", dtstart: utc("2026-10-03T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-03T10:00:00Z"), utc("2026-11-03T10:00:00Z")])
    }

    func testWindowFiltersButCountsEarlierOccurrences() {
        let dates = occ("FREQ=WEEKLY;BYDAY=MO;COUNT=4", dtstart: utc("2026-09-28T12:00:00Z"),
                        from: utc("2026-10-01T00:00:00Z"), to: utc("2026-10-12T23:59:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-05T12:00:00Z"), utc("2026-10-12T12:00:00Z")])
    }

    func testWeeklyKeepsWallClockAcrossDSTChange() {
        // DST ends 2026-10-25 in Europe/Amsterdam: 14:00 local = 12:00Z before, 13:00Z after
        let r = RecurrenceRule.parse("FREQ=WEEKLY;BYDAY=MO;COUNT=2", defaultTZ: amsterdam)!
        let dtstart = ICSDate.parse("20261019T140000", tzid: "Europe/Amsterdam", isDateValue: false, defaultTZ: amsterdam)!.date
        let dates = r.occurrences(from: dtstart, timeZone: amsterdam, windowStart: farStart, windowEnd: farEnd)
        XCTAssertEqual(dates, [utc("2026-10-19T12:00:00Z"), utc("2026-10-26T13:00:00Z")])
    }

    func testByDayBeforeDTSTARTInFirstWeekIsSkipped() {
        // dtstart Wednesday, BYDAY=MO,WE -> Monday of first week must not appear
        let dates = occ("FREQ=WEEKLY;BYDAY=MO,WE;COUNT=2", dtstart: utc("2026-09-30T12:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-30T12:00:00Z"), utc("2026-10-05T12:00:00Z")])
    }

    func testOldDailySeriesStillReachesWindow() {
        let dates = occ("FREQ=DAILY", dtstart: utc("2019-01-07T12:00:00Z"),
                        from: utc("2026-09-28T00:00:00Z"), to: utc("2026-09-30T23:59:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-28T12:00:00Z"), utc("2026-09-29T12:00:00Z"), utc("2026-09-30T12:00:00Z")])
    }

    func testOldWeeklyByDaySeriesStillReachesWindow() {
        // 2019-01-07 is a Monday
        let dates = occ("FREQ=WEEKLY;BYDAY=MO,WE", dtstart: utc("2019-01-07T12:00:00Z"),
                        from: utc("2026-09-28T00:00:00Z"), to: utc("2026-10-01T00:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-09-28T12:00:00Z"), utc("2026-09-30T12:00:00Z")])
    }

    func testOldMonthlySeriesStillReachesWindow() {
        let dates = occ("FREQ=MONTHLY;BYDAY=2TU", dtstart: utc("2019-01-08T10:00:00Z"),
                        from: utc("2026-10-01T00:00:00Z"), to: utc("2026-10-31T00:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-13T10:00:00Z")])
    }

    // MARK: - Fixes

    func testWeekStartFromWKST() {
        // 2026-10-04 is a Sunday
        let dates = occ("FREQ=WEEKLY;WKST=SU;INTERVAL=2;BYDAY=SU,MO;COUNT=4", dtstart: utc("2026-10-04T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-04T10:00:00Z"), utc("2026-10-05T10:00:00Z"),
                               utc("2026-10-18T10:00:00Z"), utc("2026-10-19T10:00:00Z")])
    }

    func testMonthlySkipsMonthsWithoutStartDay() {
        let dates = occ("FREQ=MONTHLY;COUNT=3", dtstart: utc("2026-01-31T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-01-31T10:00:00Z"), utc("2026-03-31T10:00:00Z"), utc("2026-05-31T10:00:00Z")])
    }

    func testMonthlyNegativeByMonthDay() {
        let dates = occ("FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3", dtstart: utc("2026-01-31T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-01-31T10:00:00Z"), utc("2026-02-28T10:00:00Z"), utc("2026-03-31T10:00:00Z")])
        let second = occ("FREQ=MONTHLY;BYMONTHDAY=-2;COUNT=2", dtstart: utc("2026-01-30T10:00:00Z"))
        XCTAssertEqual(second, [utc("2026-01-30T10:00:00Z"), utc("2026-02-27T10:00:00Z")])
    }

    func testMonthlyByMonthDaySkipsMissingDays() {
        let dates = occ("FREQ=MONTHLY;BYMONTHDAY=30;COUNT=2", dtstart: utc("2026-01-30T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-01-30T10:00:00Z"), utc("2026-03-30T10:00:00Z")])
    }

    func testMonthlyByDayWithoutOrdinalIsEveryWeekday() {
        // Mondays in October 2026: 5, 12, 19, 26; Wednesdays: 7, 14, 21, 28
        let mondays = occ("FREQ=MONTHLY;BYDAY=MO", dtstart: utc("2026-10-05T10:00:00Z"), to: utc("2026-10-31T00:00:00Z"))
        XCTAssertEqual(mondays, ["05", "12", "19", "26"].map { utc("2026-10-\($0)T10:00:00Z") })
        let both = occ("FREQ=MONTHLY;BYDAY=MO,WE;COUNT=4", dtstart: utc("2026-10-05T10:00:00Z"))
        XCTAssertEqual(both, ["05", "07", "12", "14"].map { utc("2026-10-\($0)T10:00:00Z") })
    }

    func testDailyByDaySkipsWeekend() {
        // 2026-10-02 is a Friday
        let dates = occ("FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=3", dtstart: utc("2026-10-02T09:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-02T09:00:00Z"), utc("2026-10-05T09:00:00Z"), utc("2026-10-06T09:00:00Z")])
    }

    func testYearlySameDay() {
        let dates = occ("FREQ=YEARLY;COUNT=2", dtstart: utc("2026-03-15T10:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-03-15T10:00:00Z"), utc("2027-03-15T10:00:00Z")])
        let biennial = occ("FREQ=YEARLY;INTERVAL=2;COUNT=2", dtstart: utc("2026-03-15T10:00:00Z"))
        XCTAssertEqual(biennial, [utc("2026-03-15T10:00:00Z"), utc("2028-03-15T10:00:00Z")])
    }

    func testYearlyLeapDayOnlyInLeapYears() {
        let dates = occ("FREQ=YEARLY;COUNT=2", dtstart: utc("2024-02-29T10:00:00Z"), from: utc("2024-01-01T00:00:00Z"), to: utc("2040-01-01T00:00:00Z"))
        XCTAssertEqual(dates, [utc("2024-02-29T10:00:00Z"), utc("2028-02-29T10:00:00Z")])
    }

    func testYearlyByMonthAndByDay() {
        // 4th Thursday of November: 2026-11-26, 2027-11-25
        let dates = occ("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=2", dtstart: utc("2026-11-26T18:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-11-26T18:00:00Z"), utc("2027-11-25T18:00:00Z")])
    }

    func testOldYearlySeriesStillReachesWindow() {
        let dates = occ("FREQ=YEARLY", dtstart: utc("2001-10-10T10:00:00Z"),
                        from: utc("2026-10-01T00:00:00Z"), to: utc("2026-10-31T00:00:00Z"))
        XCTAssertEqual(dates, [utc("2026-10-10T10:00:00Z")])
    }

    func testUnsupportedPartsAreRejected() {
        XCTAssertNil(RecurrenceRule.parse("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", defaultTZ: utcTZ))
        XCTAssertNil(RecurrenceRule.parse("FREQ=DAILY;BYHOUR=9,17", defaultTZ: utcTZ))
        XCTAssertNil(RecurrenceRule.parse("FREQ=YEARLY;BYDAY=MO", defaultTZ: utcTZ))
    }
}
