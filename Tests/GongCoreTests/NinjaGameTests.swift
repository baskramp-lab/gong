import XCTest
@testable import GongCore

final class NinjaGameTests: XCTestCase {
    /// Far from the meeting and early in the run: first spawn only after 1 s.
    let calm = 60.0

    private func run(_ g: inout NinjaGame, seconds: Double, _ input: GameInput = GameInput(), minutes: Double = 60) {
        for _ in 0..<Int(seconds * 60) { g.step(dt: 1.0 / 60, input: input, minutesToStart: minutes) }
    }

    func testStartsCentredOnFloorWithThreeLives() {
        let g = NinjaGame(seed: 1)
        XCTAssertEqual(g.x, Double(NinjaGame.width - 20) / 2)
        XCTAssertEqual(g.y, NinjaGame.floorY)
        XCTAssertEqual(g.lives, 3)
        XCTAssertEqual(g.phase, .playing)
        XCTAssertEqual(NinjaGame.spriteHeight, NinjaSprites.grid(pose: .idle).height)
    }

    func testWalksAndStopsAtArenaEdges() {
        var g = NinjaGame(seed: 1)
        g.autoSpawn = false
        run(&g, seconds: 0.5, GameInput(left: true))
        XCTAssertEqual(g.x, 104 - 30, accuracy: 0.5)
        XCTAssertEqual(g.facing, .left)
        run(&g, seconds: 5, GameInput(left: true))
        XCTAssertEqual(g.x, 0)
        run(&g, seconds: 10, GameInput(right: true))
        XCTAssertEqual(g.x, Double(NinjaGame.width - 20))
        XCTAssertEqual(g.facing, .right)
    }

    func testJumpArc() {
        var g = NinjaGame(seed: 1)
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        var peak = g.y, airborne = 0
        while g.isAirborne { run(&g, seconds: 1.0 / 60); peak = min(peak, g.y); airborne += 1 }
        XCTAssertEqual(NinjaGame.floorY - peak, 22, accuracy: 1.5)
        XCTAssertEqual(Double(airborne) / 60, 0.6, accuracy: 0.05)
        XCTAssertEqual(g.y, NinjaGame.floorY)
    }

    func testNoDoubleJump() {
        var g = NinjaGame(seed: 1)
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        run(&g, seconds: 0.1)
        XCTAssertTrue(g.isAirborne)
        var control = g
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        control.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: calm)
        XCTAssertEqual(g, control, "a jump press while airborne must not change the arc")
    }

    func testLowShurikenHitsStandingNinja() {
        var g = NinjaGame(seed: 1)
        g.spawn(Shuriken(x: g.x - 20, y: NinjaGame.lowY, vx: 60, lane: .low))
        run(&g, seconds: 0.6)
        XCTAssertEqual(g.lives, 2)
        XCTAssertGreaterThan(g.invulnerable, 0)
    }

    func testJumpClearsLowShuriken() {
        var g = NinjaGame(seed: 1)
        g.spawn(Shuriken(x: g.x - 12, y: NinjaGame.lowY, vx: 60, lane: .low))
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        run(&g, seconds: 0.55)
        XCTAssertEqual(g.lives, 3)
    }

    func testHighShurikenStillHitsWhileJumping() {
        var g = NinjaGame(seed: 1)
        g.spawn(Shuriken(x: g.x + 40, y: NinjaGame.highY, vx: -100, lane: .high))
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        run(&g, seconds: 0.5)
        XCTAssertEqual(g.lives, 2)
    }

    func testStrikeDeflectsOnlyInFacingDirection() {
        var front = NinjaGame(seed: 1) // facing right
        front.spawn(Shuriken(x: front.x + 30, y: NinjaGame.highY, vx: -60, lane: .high))
        run(&front, seconds: 0.1)
        front.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        run(&front, seconds: 0.2)
        XCTAssertEqual(front.lives, 3)
        XCTAssertTrue(front.shurikens.allSatisfy(\.deflected))

        var back = NinjaGame(seed: 1)
        back.spawn(Shuriken(x: back.x - 10, y: NinjaGame.highY, vx: 60, lane: .high))
        back.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        run(&back, seconds: 0.3)
        XCTAssertEqual(back.lives, 2)
    }

    func testDeflectEmitsEvent() {
        var g = NinjaGame(seed: 1)
        g.spawn(Shuriken(x: g.x + 22, y: NinjaGame.highY, vx: -60, lane: .high))
        g.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        var events: [GameEvent] = g.events
        for _ in 0..<12 { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: calm); events += g.events }
        XCTAssertTrue(events.contains(.deflect))
    }

    func testStrikeCooldown() {
        var g = NinjaGame(seed: 1)
        g.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        XCTAssertTrue(g.isStriking)
        run(&g, seconds: 0.3)
        XCTAssertFalse(g.isStriking)
        g.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        XCTAssertFalse(g.isStriking, "still cooling down")
        run(&g, seconds: 0.45)
        g.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        XCTAssertTrue(g.isStriking)
    }

    func testInvulnerabilityAfterHit() {
        var g = NinjaGame(seed: 1)
        g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
        g.spawn(Shuriken(x: g.x + 8, y: NinjaGame.highY, vx: 1, lane: .high))
        run(&g, seconds: 0.1)
        XCTAssertEqual(g.lives, 2, "second shuriken lands during invulnerability")
    }

    func testThreeHitsIsGameOver() {
        var g = NinjaGame(seed: 1)
        g.autoSpawn = false
        var events: [GameEvent] = []
        for _ in 0..<3 {
            g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
            for _ in 0..<(80) { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: calm); events += g.events }
        }
        XCTAssertEqual(g.lives, 0)
        XCTAssertEqual(g.phase, .gameOver)
        XCTAssertEqual(events.filter { $0 == .hit }.count, 3)
        XCTAssertEqual(events.last, .gameOver)
        let frozen = g.runTime
        run(&g, seconds: 1)
        XCTAssertEqual(g.runTime, frozen, "time stops after game over")
    }

    func testWallIsUnsurvivable() {
        var g = NinjaGame(seed: 7)
        var t = 0
        while g.phase == .playing && t < 60 * 20 {
            let input = GameInput(left: t % 120 < 60, right: t % 120 >= 60, jump: t % 20 == 0, strike: t % 7 == 0)
            g.step(dt: 1.0 / 60, input: input, minutesToStart: 0)
            t += 1
        }
        XCTAssertEqual(g.phase, .gameOver)
    }

    func testSpawnsFromBothSides() {
        var g = NinjaGame(seed: 3)
        var fromLeft = 0, fromRight = 0
        for _ in 0..<(60 * 20) {
            g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 4)
            fromLeft = max(fromLeft, g.shurikens.filter { $0.vx > 0 }.count)
            fromRight = max(fromRight, g.shurikens.filter { $0.vx < 0 }.count)
            if g.phase == .gameOver { break }
        }
        XCTAssertGreaterThan(fromLeft, 0)
        XCTAssertGreaterThan(fromRight, 0)
    }

    func testDeterministicWithSeed() {
        var a = NinjaGame(seed: 42), b = NinjaGame(seed: 42)
        run(&a, seconds: 8, minutes: 2); run(&b, seconds: 8, minutes: 2)
        XCTAssertEqual(a, b)
    }

    func testLargeDtIsClamped() {
        var g = NinjaGame(seed: 1)
        g.step(dt: 5, input: GameInput(right: true), minutesToStart: calm)
        XCTAssertEqual(g.runTime, 0.1, accuracy: 1.0 / 60)
    }

    func testShortPressBetweenTicksIsNotLost() {
        var g = NinjaGame(seed: 1)
        g.step(dt: 0.004, input: GameInput(jump: true), minutesToStart: calm)   // no tick yet
        g.step(dt: 0.02, input: GameInput(), minutesToStart: calm)
        XCTAssertTrue(g.isAirborne)
    }

    // MARK: - crouch, slide, start position, death fall

    private func quiet(_ x: Double? = nil) -> NinjaGame {
        var g = x.map { NinjaGame(seed: 1, x: $0) } ?? NinjaGame(seed: 1)
        g.autoSpawn = false
        return g
    }

    func testWorldIsAsTallAsTheScene() {
        XCTAssertEqual(NinjaGame.height, SceneLayout.modal.height)
        XCTAssertEqual(NinjaGame.floorY, Double(SceneLayout.modal.floorY))
    }

    func testStartsAtGivenX() {
        XCTAssertEqual(NinjaGame(seed: 1, x: 2).x, 2)
    }

    func testCrouchLetsHighShurikenPass() {
        var g = quiet()
        g.spawn(Shuriken(x: g.x + 40, y: NinjaGame.highY, vx: -100, lane: .high))
        run(&g, seconds: 1, GameInput(down: true))
        XCTAssertTrue(g.isCrouching)
        XCTAssertEqual(g.lives, 3)
    }

    func testCrouchStillGetsHitByLowShuriken() {
        var g = quiet()
        g.spawn(Shuriken(x: g.x + 40, y: NinjaGame.lowY, vx: -100, lane: .low))
        run(&g, seconds: 1, GameInput(down: true))
        XCTAssertEqual(g.lives, 2)
    }

    func testCrouchBlocksWalkingButTurns() {
        var g = quiet()
        let x0 = g.x
        run(&g, seconds: 0.5, GameInput(left: true, down: true))
        XCTAssertEqual(g.x, x0)
        XCTAssertEqual(g.facing, .left)
    }

    func testSlideNeedsMovement() {
        var g = quiet()
        g.step(dt: 1.0 / 60, input: GameInput(down: true, downPressed: true), minutesToStart: calm)
        XCTAssertFalse(g.isSliding)
        XCTAssertTrue(g.isCrouching)
    }

    func testSlideIsFastLowAndShort() {
        var g = quiet()
        let x0 = g.x
        g.step(dt: 1.0 / 60, input: GameInput(right: true, down: true, downPressed: true), minutesToStart: calm)
        XCTAssertTrue(g.isSliding)
        g.spawn(Shuriken(x: g.x + 30, y: NinjaGame.highY, vx: -60, lane: .high))
        run(&g, seconds: 0.4, GameInput(right: true, down: true))
        XCTAssertGreaterThan(g.x - x0, 0.4 * 60 * 1.3, "faster than walking")
        XCTAssertEqual(g.lives, 3, "high shuriken passes over the slide")
        run(&g, seconds: 0.1, GameInput(right: true))
        XCTAssertFalse(g.isSliding)
    }

    func testNoJumpOrStrikeWhileSliding() {
        var g = quiet()
        g.step(dt: 1.0 / 60, input: GameInput(right: true, down: true, downPressed: true), minutesToStart: calm)
        g.step(dt: 1.0 / 60, input: GameInput(right: true, jump: true, strike: true), minutesToStart: calm)
        XCTAssertFalse(g.isAirborne)
        XCTAssertFalse(g.isStriking)
    }

    func testNinjaFallsToTheFloorAfterGameOver() {
        var g = quiet()
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        run(&g, seconds: 0.2)
        for _ in 0..<3 {
            g.spawn(Shuriken(x: g.x + 10, y: g.y + 15, vx: 1, lane: .high))
            for _ in 0..<80 where g.phase == .playing { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: calm) }
            if g.phase == .gameOver { break }
            run(&g, seconds: 0.01)
        }
        XCTAssertEqual(g.phase, .gameOver)
        run(&g, seconds: 2)
        XCTAssertEqual(g.y, NinjaGame.floorY, "lands, never hangs in the air")
        XCTAssertFalse(g.isAirborne)
        XCTAssertGreaterThan(g.deathTime, 1.9)
    }

    func testSinceLandingCounts() {
        var g = quiet()
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: calm)
        run(&g, seconds: 0.65)
        XCTAssertLessThan(g.sinceLanding, 0.1)
    }

    // MARK: - points

    func testPointsForSurvivingAndDeflecting() {
        var g = quiet()
        run(&g, seconds: 2)
        XCTAssertEqual(g.score, 20, "10 points per second")
        g.spawn(Shuriken(x: g.x + 22, y: NinjaGame.highY, vx: -60, lane: .high))
        g.step(dt: 1.0 / 60, input: GameInput(strike: true), minutesToStart: calm)
        run(&g, seconds: 0.2)
        XCTAssertEqual(g.deflects, 1)
        XCTAssertEqual(g.score, Int(g.runTime * 10) + 50)
        XCTAssertEqual(g.pops.count, 1, "+50 pops up where the shuriken was hit")
        run(&g, seconds: 1)
        XCTAssertTrue(g.pops.isEmpty, "the pop fades after a moment")
    }

    func testScoreFreezesAtGameOver() {
        var g = quiet()
        for _ in 0..<3 {
            g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
            for _ in 0..<80 where g.phase == .playing { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: calm) }
        }
        let final = g.score
        run(&g, seconds: 2)
        XCTAssertEqual(g.score, final)
    }

    func testShurikensAreBiggerTargets() {
        XCTAssertEqual(NinjaGame.shurikenRadius, 3)
    }

    func testNonFiniteDtIsIgnored() {
        var g = NinjaGame(seed: 1)
        g.step(dt: .nan, input: GameInput(), minutesToStart: 60)
        g.step(dt: .infinity, input: GameInput(), minutesToStart: 60)
        g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60)
        XCTAssertGreaterThan(g.runTime, 0, "still ticking")
    }

    /// After game over the shurikens already in the air fly on (and off the screen); no new ones come.
    func testShurikensFlyOnAfterGameOverButNoNewOnes() {
        var g = NinjaGame(seed: 1)
        while g.phase != .gameOver { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 0) }
        XCTAssertFalse(g.shurikens.isEmpty)
        let before = g.shurikens.map(\.x)
        g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 0)
        XCTAssertNotEqual(g.shurikens.prefix(before.count).map(\.x), before, "they keep flying")
        for _ in 0..<(60 * 5) { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 0) }
        XCTAssertTrue(g.shurikens.isEmpty, "all flown off, none spawned")
    }
}
