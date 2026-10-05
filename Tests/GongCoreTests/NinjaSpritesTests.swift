import XCTest
@testable import GongCore

final class NinjaSpritesTests: XCTestCase {
    func testPoseSizes() {
        let heights: [NinjaPose: Int] = [.idle: 32, .crouch: 28, .leap: 32, .tuck: 26]
        for pose in NinjaPose.allCases {
            let g = NinjaSprites.grid(pose: pose)
            XCTAssertEqual(g.width, 20, "\(pose)")
            XCTAssertEqual(g.height, heights[pose], "\(pose)")
            XCTAssertTrue(g.lines.allSatisfy { $0.count == 20 }, "\(pose) has ragged rows")
        }
    }

    func testEveryCharacterHasAColour() {
        let known = Set(RetroPalette.ninjaRamps.keys).union(RetroPalette.ninjaFixed.keys).union(["."])
        for pose in NinjaPose.allCases {
            for ch in NinjaSprites.grid(pose: pose, blink: true).rows.joined() {
                XCTAssertTrue(known.contains(ch), "unmapped '\(ch)' in \(pose)")
            }
        }
    }

    func testBlinkClosesEyes() {
        XCTAssertTrue(NinjaSprites.grid(pose: .idle).lines[6].contains("W"))
        XCTAssertFalse(NinjaSprites.grid(pose: .idle, blink: true).lines[6].contains("W"))
    }

    func testSinkKeepsFeetPlanted() {
        let normal = NinjaSprites.grid(pose: .idle), sunk = NinjaSprites.grid(pose: .idle, sink: true)
        XCTAssertEqual(normal.lines.suffix(10), sunk.lines.suffix(10))
        XCTAssertEqual(sunk.lines[0], String(repeating: ".", count: 20))
    }

    func testRotationSwapsAxes() {
        let r = NinjaSprites.grid(pose: .tuck, rotation: 1)
        XCTAssertEqual(r.width, 26); XCTAssertEqual(r.height, 20)
    }
}
