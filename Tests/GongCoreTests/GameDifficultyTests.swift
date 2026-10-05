import XCTest
@testable import GongCore

final class GameDifficultyTests: XCTestCase {
    func testCalmWhenModalOpens() {
        let p = GameDifficulty.params(minutesToStart: 5, runTime: 0)
        XCTAssertEqual(p.interval, 1.6, accuracy: 1e-9)
        XCTAssertEqual(p.speed, 50, accuracy: 1e-9)
        XCTAssertEqual(p.highChance, 0.3, accuracy: 1e-9)
        XCTAssertFalse(p.wall)
    }

    func testHardestJustBeforeStart() {
        let p = GameDifficulty.params(minutesToStart: 0.001, runTime: 0)
        XCTAssertEqual(p.interval, 0.35, accuracy: 0.001)
        XCTAssertEqual(p.speed, 110, accuracy: 0.1)
        XCTAssertFalse(p.wall)
    }

    func testRampWithinRunCapsAtSixtyPercent() {
        let early = GameDifficulty.params(minutesToStart: 10, runTime: 0)
        let late = GameDifficulty.params(minutesToStart: 10, runTime: 500)
        XCTAssertEqual(early.speed, 50, accuracy: 1e-9)
        XCTAssertEqual(late.speed, 50 + 60 * 0.6, accuracy: 1e-9)
    }

    func testWallOnceMeetingStarted() {
        for m in [0.0, -3] {
            let p = GameDifficulty.params(minutesToStart: m, runTime: 0)
            XCTAssertTrue(p.wall)
            XCTAssertEqual(p.interval, 0.25)
            XCTAssertEqual(p.speed, 120)
        }
    }

    func testFontHasGameOverGlyphs() {
        for ch in "GAME OVERNEW HI!0123456789:" { XCTAssertNotNil(PixelFont.glyphs[ch], "missing \(ch)") }
    }
}
