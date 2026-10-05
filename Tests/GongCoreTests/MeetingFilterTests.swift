import XCTest
@testable import GongCore

final class MeetingFilterTests: XCTestCase {
    let me = "alex@example.com"

    func event(title: String, allDay: Bool = false, myStatus: ParticipationStatus = .accepted,
               others: [String] = [], meet: String? = nil, start: String = "2026-09-28T12:00:00Z") -> Event {
        var attendees = others.map { Attendee(email: $0, name: nil, status: .accepted) }
        if myStatus != .unknown { attendees.append(Attendee(email: me, name: "Bas", status: myStatus)) }
        return Event(id: title, uid: title, title: title, start: utc(start), end: utc(start).addingTimeInterval(1800),
                     isAllDay: allDay, attendees: attendees, myStatus: myStatus,
                     meetURL: meet.flatMap(URL.init(string:)), description: nil, location: nil)
    }

    func testKeepsMeetingWithOtherAttendee() {
        let m = MeetingFilter.meetings(from: [event(title: "A", others: ["sam@example.org"])], myEmail: me)
        XCTAssertEqual(m.map(\.title), ["A"])
    }

    func testKeepsSoloEventWithMeetLink() {
        let m = MeetingFilter.meetings(from: [event(title: "B", myStatus: .unknown, meet: "https://meet.google.com/a-b-c")], myEmail: me)
        XCTAssertEqual(m.map(\.title), ["B"])
    }

    func testDropsSoloEventWithoutLink() {
        XCTAssertTrue(MeetingFilter.meetings(from: [event(title: "Focus", myStatus: .unknown)], myEmail: me).isEmpty)
    }

    func testDropsEventWhereOnlyAttendeeIsMe() {
        XCTAssertTrue(MeetingFilter.meetings(from: [event(title: "Self", myStatus: .accepted)], myEmail: me).isEmpty)
    }

    func testDropsDeclined() {
        XCTAssertTrue(MeetingFilter.meetings(from: [event(title: "No", myStatus: .declined, others: ["x@y.z"], meet: "https://meet.google.com/x")], myEmail: me).isEmpty)
    }

    func testDropsAllDay() {
        XCTAssertTrue(MeetingFilter.meetings(from: [event(title: "Dag", allDay: true, others: ["x@y.z"])], myEmail: me).isEmpty)
    }

    func testKeepsTentativeAndNeedsAction() {
        let events = [event(title: "T", myStatus: .tentative, others: ["x@y.z"]), event(title: "N", myStatus: .needsAction, others: ["x@y.z"])]
        XCTAssertEqual(MeetingFilter.meetings(from: events, myEmail: me).count, 2)
    }

    func testIncludeUnacceptedOffDropsTentativeAndNeedsAction() {
        let events = [event(title: "A", myStatus: .accepted, others: ["x@y.z"]),
                      event(title: "T", myStatus: .tentative, others: ["x@y.z"]),
                      event(title: "N", myStatus: .needsAction, others: ["x@y.z"])]
        XCTAssertEqual(MeetingFilter.meetings(from: events, myEmail: me, includeUnaccepted: false).map(\.title), ["A"])
    }

    func testIncludeUnacceptedOffKeepsOwnEventWithMeetLink() {
        // I'm not in the attendee list (own event), so there is nothing to accept: keep it.
        let m = MeetingFilter.meetings(from: [event(title: "Own", myStatus: .unknown, meet: "https://meet.google.com/a-b-c")],
                                       myEmail: me, includeUnaccepted: false)
        XCTAssertEqual(m.map(\.title), ["Own"])
    }

    func testSortedByStart() {
        let events = [event(title: "Late", others: ["x@y.z"], start: "2026-09-28T15:00:00Z"),
                      event(title: "Early", others: ["x@y.z"], start: "2026-09-28T09:00:00Z")]
        XCTAssertEqual(MeetingFilter.meetings(from: events, myEmail: me).map(\.title), ["Early", "Late"])
    }

    func testEmailComparisonIsCaseInsensitive() {
        let e = event(title: "C", others: ["ALEX@example.com"])
        // the "other" attendee is actually me in different casing -> no real other attendee
        let stripped = Event(id: e.id, uid: e.uid, title: e.title, start: e.start, end: e.end, isAllDay: false,
                             attendees: [Attendee(email: "ALEX@example.com", name: nil, status: .accepted)],
                             myStatus: .accepted, meetURL: nil, description: nil, location: nil)
        XCTAssertTrue(MeetingFilter.meetings(from: [stripped], myEmail: me).isEmpty)
    }
}
