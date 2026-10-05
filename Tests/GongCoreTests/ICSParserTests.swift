import XCTest
@testable import GongCore

final class ICSParserTests: XCTestCase {
    let me = "alex@example.com"
    let window = ParseWindow(start: utc("2026-09-28T00:00:00Z"), end: utc("2026-09-30T00:00:00Z"))

    let single = """
    BEGIN:VEVENT
    DTSTART;TZID=Europe/Amsterdam:20260928T140000
    DTEND;TZID=Europe/Amsterdam:20260928T150000
    UID:abc123@google.com
    SUMMARY:Sprint Review\\, week 40
    DESCRIPTION:Eerste regel\\nTweede regel
    LOCATION:Zwolle
    STATUS:CONFIRMED
    X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij
    ATTENDEE;CUTYPE=INDIVIDUAL;PARTSTAT=ACCEPTED;CN=Alex Example:mailto:Alex@example.com
    ATTENDEE;CUTYPE=INDIVIDUAL;PARTSTAT=NEEDS-ACTION;CN=Sam:mailto:sam@example.org
    END:VEVENT
    """

    func testSingleEventFields() {
        let events = ICSParser.parse(ics(single), myEmail: me, window: window)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.uid, "abc123@google.com")
        XCTAssertEqual(e.calendarEventID, "abc123")
        XCTAssertEqual(e.title, "Sprint Review, week 40")
        XCTAssertEqual(e.start, utc("2026-09-28T12:00:00Z"))
        XCTAssertEqual(e.end, utc("2026-09-28T13:00:00Z"))
        XCTAssertFalse(e.isAllDay)
        XCTAssertEqual(e.description, "Eerste regel\nTweede regel")
        XCTAssertEqual(e.location, "Zwolle")
        XCTAssertEqual(e.meetURL, URL(string: "https://meet.google.com/abc-defg-hij"))
        XCTAssertEqual(e.myStatus, .accepted)
        XCTAssertEqual(e.attendees.count, 2)
        XCTAssertEqual(e.attendees[1], Attendee(email: "sam@example.org", name: "Sam", status: .needsAction))
        XCTAssertEqual(e.id, Event.makeID(uid: "abc123@google.com", start: utc("2026-09-28T12:00:00Z")))
    }

    func testMeetLinkFromDescriptionWhenNoConferenceProperty() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T120000Z
        DTEND:20260928T123000Z
        UID:x1
        SUMMARY:Sync
        DESCRIPTION:Join here: https://meet.google.com/zzz-yyyy-xxx and thanks
        END:VEVENT
        """
        let e = ICSParser.parse(ics(body), myEmail: me, window: window)[0]
        XCTAssertEqual(e.meetURL, URL(string: "https://meet.google.com/zzz-yyyy-xxx"))
    }

    func testZoomInLocation() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T120000Z
        DTEND:20260928T123000Z
        UID:x2
        SUMMARY:Zoom
        LOCATION:https://acme.zoom.us/j/123456
        END:VEVENT
        """
        let e = ICSParser.parse(ics(body), myEmail: me, window: window)[0]
        XCTAssertEqual(e.meetURL?.host, "acme.zoom.us")
    }

    func testAllDay() {
        let body = """
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260928
        DTEND;VALUE=DATE:20260929
        UID:x3
        SUMMARY:Vrij
        END:VEVENT
        """
        // midnight Amsterdam = 2026-09-27T22:00Z, so widen the window to the day before
        let w = ParseWindow(start: utc("2026-09-27T00:00:00Z"), end: utc("2026-09-30T00:00:00Z"))
        let events = ICSParser.parse(ics(body), myEmail: me, window: w, defaultTZ: amsterdam)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isAllDay)
    }

    func testOutsideWindowIsDropped() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20261005T120000Z
        DTEND:20261005T123000Z
        UID:x4
        SUMMARY:Later
        END:VEVENT
        """
        XCTAssertTrue(ICSParser.parse(ics(body), myEmail: me, window: window).isEmpty)
    }

    func testCancelledIsDropped() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T120000Z
        DTEND:20260928T123000Z
        UID:x5
        SUMMARY:Geannuleerd
        STATUS:CANCELLED
        END:VEVENT
        """
        XCTAssertTrue(ICSParser.parse(ics(body), myEmail: me, window: window).isEmpty)
    }

    func testMyStatusDeclinedAndUnknown() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T120000Z
        DTEND:20260928T123000Z
        UID:x6
        SUMMARY:Afgewezen
        ATTENDEE;PARTSTAT=DECLINED:mailto:alex@example.com
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20260928T130000Z
        DTEND:20260928T133000Z
        UID:x7
        SUMMARY:Eigen blok
        END:VEVENT
        """
        let events = ICSParser.parse(ics(body), myEmail: me, window: window)
        XCTAssertEqual(events.map(\.myStatus), [.declined, .unknown])
    }

    func testSortedByStart() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T150000Z
        DTEND:20260928T153000Z
        UID:b
        SUMMARY:B
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20260928T100000Z
        DTEND:20260928T103000Z
        UID:a
        SUMMARY:A
        END:VEVENT
        """
        XCTAssertEqual(ICSParser.parse(ics(body), myEmail: me, window: window).map(\.title), ["A", "B"])
    }

    func testMissingDTENDGivesZeroDuration() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T150000Z
        UID:c
        SUMMARY:C
        END:VEVENT
        """
        let e = ICSParser.parse(ics(body), myEmail: me, window: window)[0]
        XCTAssertEqual(e.end, e.start)
    }

    // MARK: - Recurrence

    let weekWindow = ParseWindow(start: utc("2026-09-28T00:00:00Z"), end: utc("2026-10-20T00:00:00Z"))

    let weekly = """
    BEGIN:VEVENT
    DTSTART:20260928T120000Z
    DTEND:20260928T130000Z
    RRULE:FREQ=WEEKLY;BYDAY=MO
    UID:rec1@google.com
    SUMMARY:Weekly
    END:VEVENT
    """

    func testWeeklyExpandsInsideWindow() {
        let events = ICSParser.parse(ics(weekly), myEmail: me, window: weekWindow)
        XCTAssertEqual(events.map(\.start), [utc("2026-09-28T12:00:00Z"), utc("2026-10-05T12:00:00Z"),
                                              utc("2026-10-12T12:00:00Z"), utc("2026-10-19T12:00:00Z")])
        XCTAssertEqual(Set(events.map(\.id)).count, 4)
        XCTAssertEqual(events[1].end, utc("2026-10-05T13:00:00Z"))
    }

    func testExdateRemovesInstance() {
        let body = weekly.replacingOccurrences(of: "RRULE:FREQ=WEEKLY;BYDAY=MO", with: "RRULE:FREQ=WEEKLY;BYDAY=MO\nEXDATE:20261005T120000Z")
        let events = ICSParser.parse(ics(body), myEmail: me, window: weekWindow)
        XCTAssertEqual(events.count, 3)
        XCTAssertFalse(events.map(\.start).contains(utc("2026-10-05T12:00:00Z")))
    }

    func testRecurrenceIDOverrideReplacesInstance() {
        let override = """
        BEGIN:VEVENT
        DTSTART:20261006T090000Z
        DTEND:20261006T100000Z
        RECURRENCE-ID:20261005T120000Z
        UID:rec1@google.com
        SUMMARY:Weekly (verplaatst)
        END:VEVENT
        """
        let events = ICSParser.parse(ics(weekly + "\n" + override), myEmail: me, window: weekWindow)
        XCTAssertEqual(events.count, 4)
        XCTAssertFalse(events.map(\.start).contains(utc("2026-10-05T12:00:00Z")))
        let moved = events.first { $0.start == utc("2026-10-06T09:00:00Z") }
        XCTAssertEqual(moved?.title, "Weekly (verplaatst)")
    }

    func testCancelledOverrideRemovesInstance() {
        let override = """
        BEGIN:VEVENT
        DTSTART:20261005T120000Z
        DTEND:20261005T130000Z
        RECURRENCE-ID:20261005T120000Z
        UID:rec1@google.com
        SUMMARY:Weekly
        STATUS:CANCELLED
        END:VEVENT
        """
        let events = ICSParser.parse(ics(weekly + "\n" + override), myEmail: me, window: weekWindow)
        XCTAssertEqual(events.count, 3)
    }

    func testCancelledMasterProducesNothing() {
        let body = weekly.replacingOccurrences(of: "SUMMARY:Weekly", with: "SUMMARY:Weekly\nSTATUS:CANCELLED")
        XCTAssertTrue(ICSParser.parse(ics(body), myEmail: me, window: weekWindow).isEmpty)
    }

    func testCancelledMasterSuppressesLiveOverride() {
        let cancelledMaster = weekly.replacingOccurrences(of: "SUMMARY:Weekly", with: "SUMMARY:Weekly\nSTATUS:CANCELLED")
        let override = """
        BEGIN:VEVENT
        DTSTART:20261006T090000Z
        DTEND:20261006T100000Z
        RECURRENCE-ID:20261005T120000Z
        UID:rec1@google.com
        SUMMARY:Weekly (verplaatst)
        END:VEVENT
        """
        XCTAssertTrue(ICSParser.parse(ics(cancelledMaster + "\n" + override), myEmail: me, window: weekWindow).isEmpty)
    }

    func testUnsupportedRRULEIsSkippedButOthersParse() {
        let yearly = """
        BEGIN:VEVENT
        DTSTART:20260928T150000Z
        DTEND:20260928T160000Z
        RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1
        UID:y1
        SUMMARY:Jaarlijks
        END:VEVENT
        """
        let events = ICSParser.parse(ics(weekly + "\n" + yearly), myEmail: me, window: weekWindow)
        XCTAssertEqual(events.count, 4)
        XCTAssertFalse(events.map(\.title).contains("Jaarlijks"))
    }

    func testRecurrenceWithTZIDKeepsWallClockAfterDST() {
        let body = """
        BEGIN:VEVENT
        DTSTART;TZID=Europe/Amsterdam:20261019T140000
        DTEND;TZID=Europe/Amsterdam:20261019T150000
        RRULE:FREQ=WEEKLY;BYDAY=MO
        UID:dst@google.com
        SUMMARY:DST
        END:VEVENT
        """
        let w = ParseWindow(start: utc("2026-10-19T00:00:00Z"), end: utc("2026-10-27T00:00:00Z"))
        let events = ICSParser.parse(ics(body), myEmail: me, window: w)
        XCTAssertEqual(events.map(\.start), [utc("2026-10-19T12:00:00Z"), utc("2026-10-26T13:00:00Z")])
    }

    // MARK: - Nested components, DURATION

    func testAlarmPropertiesDoNotLeakIntoEvent() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T120000Z
        DTEND:20260928T123000Z
        UID:alarm1
        SUMMARY:Standup
        DESCRIPTION:Join: https://acme.zoom.us/j/123456
        ATTENDEE;PARTSTAT=ACCEPTED:mailto:alex@example.com
        BEGIN:VALARM
        ACTION:DISPLAY
        DESCRIPTION:This is an event reminder
        TRIGGER:-P0DT0H10M0S
        END:VALARM
        BEGIN:VALARM
        ACTION:EMAIL
        SUMMARY:Alarm notification
        DESCRIPTION:This is an event reminder
        ATTENDEE:mailto:someone@example.com
        TRIGGER:-P0DT0H30M0S
        END:VALARM
        END:VEVENT
        """
        let events = ICSParser.parse(ics(body), myEmail: me, window: window)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.title, "Standup")
        XCTAssertEqual(e.description, "Join: https://acme.zoom.us/j/123456")
        XCTAssertEqual(e.meetURL?.host, "acme.zoom.us")
        XCTAssertEqual(e.attendees.map(\.email), ["alex@example.com"])
        XCTAssertEqual(e.end, utc("2026-09-28T12:30:00Z"))
    }

    func testDurationWithoutDTEND() {
        let body = """
        BEGIN:VEVENT
        DTSTART:20260928T120000Z
        DURATION:PT1H30M
        UID:dur1
        SUMMARY:Long
        END:VEVENT
        """
        let e = ICSParser.parse(ics(body), myEmail: me, window: window)[0]
        XCTAssertEqual(e.end, utc("2026-09-28T13:30:00Z"))
    }

    func testParseDuration() {
        XCTAssertEqual(ICSParser.parseDuration("PT15M"), DateComponents(minute: 15))
        XCTAssertEqual(ICSParser.parseDuration("+P1DT2H3M4S"), DateComponents(day: 1, hour: 2, minute: 3, second: 4))
        XCTAssertEqual(ICSParser.parseDuration("P2W"), DateComponents(day: 14))
        XCTAssertEqual(ICSParser.parseDuration("-PT5M"), DateComponents(minute: -5))
        XCTAssertNil(ICSParser.parseDuration("P"))
        XCTAssertNil(ICSParser.parseDuration("1H"))
        XCTAssertNil(ICSParser.parseDuration("P1M"))
    }
}
