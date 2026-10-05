import XCTest
@testable import GongCore

final class SchedulerTests: XCTestCase {
    let start = utc("2026-09-28T12:00:00Z")
    var now = utc("2026-09-28T11:00:00Z")
    lazy var scheduler = Scheduler(config: SchedulerConfig(), now: { self.now })

    func meeting(_ id: String = "m1", start: Date? = nil) -> Meeting {
        let s = start ?? self.start
        return Event(id: id, uid: id, title: id, start: s, end: s.addingTimeInterval(1800), isAllDay: false,
                     attendees: [Attendee(email: "x@y.z", name: nil, status: .accepted)], myStatus: .accepted,
                     meetURL: URL(string: "https://meet.google.com/a-b-c"), description: nil, location: nil)
    }

    func at(minutesBefore: Double) { now = start.addingTimeInterval(-minutesBefore * 60) }

    func testNothingFarBefore() {
        at(minutesBefore: 40)
        let r = scheduler.tick(meetings: [meeting()])
        XCTAssertEqual(r, TickResult())
    }

    func testSoft30ThenSoft10ThenBlocking_noDuplicates() {
        at(minutesBefore: 30)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).notifications.map(\.minutesBefore), [30])
        at(minutesBefore: 29)
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).notifications.isEmpty)
        at(minutesBefore: 10)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).notifications.map(\.minutesBefore), [10])
        at(minutesBefore: 9.5)
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).notifications.isEmpty)
        at(minutesBefore: 5)
        let r = scheduler.tick(meetings: [meeting()])
        XCTAssertEqual(r.blocking.map(\.id), ["m1"])
        XCTAssertTrue(r.notifications.isEmpty)
        at(minutesBefore: 4.5)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).blocking.map(\.id), ["m1"])
    }

    func testLateStartOnlyHighestThreshold() {
        at(minutesBefore: 8)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).notifications.map(\.minutesBefore), [10])
        let fresh = Scheduler(config: SchedulerConfig(), now: { self.now })
        at(minutesBefore: 4)
        let r = fresh.tick(meetings: [meeting()])
        XCTAssertTrue(r.notifications.isEmpty)
        XCTAssertEqual(r.blocking.count, 1)
    }

    func testHandledNeverReturns() {
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [meeting()])
        scheduler.handle("m1")
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        at(minutesBefore: 0)
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        XCTAssertEqual(scheduler.states["m1"], .handled)
    }

    func testSnoozeReturnsAfterTwoMinutes() {
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [meeting()])
        scheduler.snooze("m1")
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        at(minutesBefore: 3)
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        at(minutesBefore: 2)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).blocking.map(\.id), ["m1"])
    }

    func testSnoozeAfterStartStillComesBack() {
        at(minutesBefore: -3)
        _ = scheduler.tick(meetings: [meeting()])
        scheduler.snooze("m1")
        at(minutesBefore: -5)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).blocking.count, 1)
    }

    func testWakeFromSleepWithinGraceBlocks() {
        at(minutesBefore: -12)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).blocking.count, 1)
    }

    func testWakeFromSleepBeyondGraceIsHandled() {
        at(minutesBefore: -20)
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        XCTAssertEqual(scheduler.states["m1"], .handled)
    }

    func testBlockingSurvivesBeyondGraceOnceShown() {
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [meeting()])
        at(minutesBefore: -20)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).blocking.count, 1)
    }

    func testPauseSuppressesEverythingAndSkipsMeetingsThatStartedDuringPause() {
        at(minutesBefore: 30)
        scheduler.pause(until: now.addingTimeInterval(3600))
        XCTAssertTrue(scheduler.isPaused)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]), TickResult())
        at(minutesBefore: 5)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]), TickResult())
        at(minutesBefore: -1)
        _ = scheduler.tick(meetings: [meeting()])
        at(minutesBefore: -31) // pause expired
        XCTAssertFalse(scheduler.isPaused)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]), TickResult())
        XCTAssertEqual(scheduler.states["m1"], .handled)
    }

    func testPauseDoesNotSkipMeetingStartingAfterPauseEnds() {
        at(minutesBefore: 20)
        scheduler.pause(until: now.addingTimeInterval(10 * 60))
        at(minutesBefore: 12)
        _ = scheduler.tick(meetings: [meeting()])
        at(minutesBefore: 9)
        XCTAssertEqual(scheduler.tick(meetings: [meeting()]).notifications.map(\.minutesBefore), [10])
    }

    func testMeetingRemovedFromFeedWhileBlocking() {
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [meeting()])
        let r = scheduler.tick(meetings: [])
        XCTAssertTrue(r.blocking.isEmpty)
        XCTAssertNil(scheduler.states["m1"])
    }

    func testTwoMeetingsBlockTogetherSortedByStart() {
        let m2 = meeting("m2", start: start.addingTimeInterval(60))
        at(minutesBefore: 4)
        XCTAssertEqual(scheduler.tick(meetings: [m2, meeting()]).blocking.map(\.id), ["m1", "m2"])
    }

    func testPersistedHandledStateIsRespected() {
        let s = Scheduler(config: SchedulerConfig(), states: ["m1": .handled], now: { self.now })
        at(minutesBefore: 4)
        XCTAssertTrue(s.tick(meetings: [meeting()]).blocking.isEmpty)
    }

    func testNextMeetingSkipsHandledAndPast() {
        at(minutesBefore: 4)
        let m2 = meeting("m2", start: start.addingTimeInterval(3600))
        _ = scheduler.tick(meetings: [meeting(), m2])
        scheduler.handle("m1")
        XCTAssertEqual(scheduler.nextMeeting(in: [meeting(), m2])?.id, "m2")
    }

    func testBlockingExpiresAfterMeetingEnd() {
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [meeting()])
        now = start.addingTimeInterval(1800 + 60) // meeting() lasts 30 min
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        XCTAssertEqual(scheduler.states["m1"], .handled)
    }

    func testSnoozedExpiresAfterMeetingEnd() {
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [meeting()])
        scheduler.snooze("m1")
        now = start.addingTimeInterval(1800 + 60) // meeting() lasts 30 min
        XCTAssertTrue(scheduler.tick(meetings: [meeting()]).blocking.isEmpty)
        XCTAssertEqual(scheduler.states["m1"], .handled)
    }

    func testStateRoundTripsThroughJSON() throws {
        let states: [String: MeetingState] = ["a": .quiet, "b": .softSent(minutes: 10), "c": .blocking,
                                              "d": .snoozed(until: start), "e": .handled]
        let data = try JSONEncoder().encode(states)
        XCTAssertEqual(try JSONDecoder().decode([String: MeetingState].self, from: data), states)
    }

    /// A meeting that briefly drops out of the list (filter toggled, short feed) keeps its handled/snoozed state.
    func testStateSurvivesMeetingDroppingOutOfTheList() {
        let id = "u1/\(Int(start.timeIntervalSince1970))"
        let m = meeting(id)
        at(minutesBefore: 4)
        _ = scheduler.tick(meetings: [m])
        scheduler.handle(id)
        _ = scheduler.tick(meetings: [])
        now = start.addingTimeInterval(60)
        XCTAssertTrue(scheduler.tick(meetings: [m]).blocking.isEmpty, "closed modal stays closed")
        now = start.addingTimeInterval(25 * 3600)
        _ = scheduler.tick(meetings: [])
        XCTAssertNil(scheduler.states[id], "forgotten a day after the start")
    }

    /// Waking or launching after a short meeting has ended does not block for it.
    func testEndedMeetingNeverBlocks() {
        let short = Event(id: "s", uid: "s", title: "s", start: start, end: start.addingTimeInterval(300), isAllDay: false,
                          attendees: [Attendee(email: "x@y.z", name: nil, status: .accepted)], myStatus: .accepted,
                          meetURL: nil, description: nil, location: nil)
        now = start.addingTimeInterval(600)
        XCTAssertTrue(scheduler.tick(meetings: [short]).blocking.isEmpty)
        XCTAssertEqual(scheduler.states["s"], .handled)
    }
}
