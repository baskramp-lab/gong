import XCTest
@testable import GongCore

final class SpriteGridTests: XCTestCase {
    let g = SpriteGrid(["ab.", "cd."])   // 3 wide, 2 tall

    func testParseAndOutOfBounds() {
        XCTAssertEqual(g.width, 3)
        XCTAssertEqual(g.height, 2)
        XCTAssertEqual(g[1, 1], "d")
        XCTAssertEqual(g[5, 0], ".")
        XCTAssertEqual(g[0, -1], ".")
    }

    func testShortRowsArePadded() {
        let p = SpriteGrid(["abc", "d"])
        XCTAssertEqual(p[2, 1], ".")
        XCTAssertEqual(p.width, 3)
    }

    func testRotateClockwise() {
        let r = g.rotated(quarterTurns: 1)
        XCTAssertEqual(r.width, 2); XCTAssertEqual(r.height, 3)
        XCTAssertEqual(r.lines, ["ca", "db", ".."])
    }

    func testRotate180And270() {
        XCTAssertEqual(g.rotated(quarterTurns: 2).lines, [".dc", ".ba"])
        XCTAssertEqual(g.rotated(quarterTurns: 3).lines, ["..", "bd", "ac"])
        XCTAssertEqual(g.rotated(quarterTurns: 4), g)
    }

    func testSunkShiftsUpperRowsKeepsLower() {
        let s = SpriteGrid(["aa", "bb", "cc", "dd"]).sunk(upperRows: 3)
        XCTAssertEqual(s.lines, ["..", "aa", "bb", "dd"])
    }

    func testConcat() {
        XCTAssertEqual((SpriteGrid(["a"]) + SpriteGrid(["b"])).lines, ["a", "b"])
    }
}
