import XCTest
@testable import GongCore

final class StrikeClockTests: XCTestCase {
    let start = utc("2026-10-01T12:00:00Z")

    func testFirstStrikeAfterOpen() {
        let clock = StrikeClock(start: start)
        XCTAssertEqual(clock.nextStrike(after: start), start.addingTimeInterval(1.82))
        XCTAssertEqual(clock.nextStrike(after: start.addingTimeInterval(-5)), start.addingTimeInterval(1.82))
    }

    func testStrikesEveryFourSeconds() {
        let clock = StrikeClock(start: start)
        let first = clock.nextStrike(after: start)
        XCTAssertEqual(clock.nextStrike(after: first), start.addingTimeInterval(5.82))
        XCTAssertEqual(clock.nextStrike(after: start.addingTimeInterval(12)), start.addingTimeInterval(13.82))
    }

    func testCycleTimeWraps() {
        let clock = StrikeClock(start: start)
        XCTAssertEqual(clock.cycleTime(at: start.addingTimeInterval(14.5)), 1.5, accuracy: 1e-9)
        XCTAssertEqual(clock.cycleTime(at: start.addingTimeInterval(1)), 0, accuracy: 1e-9)
    }

    func testIdleDuringLeadIn() {
        let clock = StrikeClock(start: start)
        for t in [-3.0, 0, 0.5, 0.99] {
            let st = StrikeTimeline.state(cycleTime: clock.cycleTime(at: start.addingTimeInterval(t)), time: t, reduceMotion: false)
            XCTAssertEqual(st.pose, .idle, "t=\(t)")
        }
    }
}

final class StrikeTimelineTests: XCTestCase {
    let layout = SceneLayout.modal

    private func s(_ cycle: Double, time: Double? = nil, reduceMotion: Bool = false) -> SceneState {
        StrikeTimeline.state(cycleTime: cycle, time: time ?? cycle, reduceMotion: reduceMotion, layout: layout)
    }

    func testLayoutGeometry() {
        XCTAssertEqual(layout.gongRadius, 20)
        XCTAssertEqual(layout.gongX, 70)
        XCTAssertEqual(layout.gongY, 50)
        XCTAssertEqual(layout.floorY, 54)
        XCTAssertEqual(layout.homeX, 2)
        XCTAssertEqual(layout.strikeX, 20)
    }

    func testCrouchAtStart() {
        let st = s(0.2)
        XCTAssertEqual(st.pose, .crouch)
        XCTAssertEqual(st.y, Double(layout.floorY + 4))
        XCTAssertEqual(st.staff, .swing(angle: -2.4, length: 16))
    }

    func testLeapHasGhostsAndSpeedLines() {
        let st = s(0.6)
        XCTAssertEqual(st.pose, .leap)
        XCTAssertGreaterThan(st.x, layout.homeX)
        XCTAssertLessThan(st.x, layout.strikeX)
        XCTAssertEqual(st.ghosts.count, 3)
        XCTAssertTrue(st.speedLines)
    }

    func testHitStopFreezesAndFlashes() {
        let a = s(0.85), b = s(0.9)
        XCTAssertEqual(a.x, b.x); XCTAssertEqual(a.y, b.y)
        XCTAssertEqual(a.x, layout.strikeX)
        XCTAssertTrue(a.gongFlash)
        XCTAssertFalse(s(0.95).gongFlash)
        XCTAssertFalse(s(0.8).gongFlash)
        if case .swing(let angle, _) = a.staff { XCTAssertEqual(angle, 0) } else { XCTFail("expected horizontal swing") }
    }

    func testEffectsAfterHit() {
        let st = s(1.0)
        XCTAssertNotNil(st.ringsTime)
        XCTAssertNotNil(st.textTime)
        XCTAssertNotEqual(st.gongShake, 0)
        XCTAssertNil(s(2.0).textTime)
        XCTAssertNil(s(5).ringsTime)
    }

    func testSaltoBackHome() {
        let st = s(1.2)
        XCTAssertEqual(st.pose, .tuck)
        XCTAssertEqual(st.staff, .none)
        XCTAssertTrue((0...3).contains(st.rotation))
        let rotations = Set(stride(from: 1.03, to: 1.6, by: 0.01).map { s($0).rotation })
        XCTAssertEqual(rotations, [0, 1, 2, 3])
    }

    func testIdleIsGuardWithoutEffects() {
        let st = s(5)
        XCTAssertEqual(st.pose, .idle)
        XCTAssertEqual(st.x, layout.homeX)
        if case .guardStance = st.staff {} else { XCTFail("expected guard") }
        XCTAssertNil(st.ringsTime); XCTAssertNil(st.textTime)
        XCTAssertFalse(st.gongFlash); XCTAssertEqual(st.cameraShake, 0)
    }

    func testReduceMotionStaysInGuard() {
        for t in [0.2, 0.6, 0.85, 1.0, 1.2] {
            let st = s(t, reduceMotion: true)
            XCTAssertEqual(st.pose, .idle, "t=\(t)")
            XCTAssertFalse(st.gongFlash); XCTAssertEqual(st.gongShake, 0); XCTAssertEqual(st.cameraShake, 0)
            XCTAssertNil(st.ringsTime); XCTAssertNil(st.textTime)
        }
    }

    func testHorizontalMotionIsContinuous() {
        var prev = s(0).x
        for i in 1...(4 * 60) {
            let x = s(Double(i) / 60).x
            XCTAssertLessThanOrEqual(abs(x - prev), 3, "jump at t=\(Double(i) / 60)")
            prev = x
        }
    }

    func testBreathingAndBlinkFollowGlobalTime() {
        XCTAssertNotEqual(s(5, time: 0.1).sink, s(5, time: 0.9).sink)
        XCTAssertTrue(s(5, time: 3.15).blink)
        XCTAssertFalse(s(5, time: 1.0).blink)
    }

    /// Take-off (0.4…0.7 s) uses the game ninja; crouch before and strike / salto after keep the sprites.
    func testRigJumpOnlyDuringTakeOff() {
        XCTAssertNil(s(0.3).rigJump)
        XCTAssertEqual(s(0.4).rigJump ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(s(0.55).rigJump ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertNil(s(0.75).rigJump, "the strike keeps the sprite")
        XCTAssertNil(s(1.2).rigJump, "the salto keeps the sprite")
        XCTAssertNil(s(5).rigJump)
        XCTAssertNil(s(0.55, reduceMotion: true).rigJump)
    }
}
