import XCTest
@testable import GongCore

final class CalendarIdentityTests: XCTestCase {
    func testEmailFromSecretICalURL() {
        XCTAssertEqual(CalendarIdentity.email(fromICalURL: "https://calendar.google.com/calendar/ical/alex%40example.com/private-abc123/basic.ics"),
                       "alex@example.com")
        XCTAssertEqual(CalendarIdentity.email(fromICalURL: "https://calendar.google.com/calendar/ical/Alex.Example@Example.com/private-x/basic.ics"),
                       "alex.example@example.com")
    }

    func testNoEmailForOtherURLs() {
        XCTAssertNil(CalendarIdentity.email(fromICalURL: "https://calendar.google.com/calendar/ical/abc123/basic.ics"))
        XCTAssertNil(CalendarIdentity.email(fromICalURL: "not a url"))
        XCTAssertNil(CalendarIdentity.email(fromICalURL: nil))
    }

    func testSettingWinsOverURL() {
        XCTAssertEqual(CalendarIdentity.myEmail(setting: " Me@Example.com ", icalURL: "https://calendar.google.com/calendar/ical/other%40example.com/private-x/basic.ics"),
                       "me@example.com")
        XCTAssertEqual(CalendarIdentity.myEmail(setting: "", icalURL: "https://calendar.google.com/calendar/ical/other%40example.com/private-x/basic.ics"),
                       "other@example.com")
        XCTAssertEqual(CalendarIdentity.myEmail(setting: "", icalURL: nil), "")
    }

    func testDefaultSettingsCarryNoEmail() {
        XCTAssertEqual(AppSettings.default.myEmail, "")
    }
}
