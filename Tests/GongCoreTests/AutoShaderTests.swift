import XCTest
@testable import GongCore

final class AutoShaderTests: XCTestCase {
    let ramp = [RGBA(hex: 0x000000), RGBA(hex: 0x111111), RGBA(hex: 0x222222), RGBA(hex: 0x333333)]

    private func color(_ px: [ShadedPixel], _ x: Int, _ y: Int) -> RGBA? {
        px.first { $0.x == x && $0.y == y }?.color
    }

    func testBlockShading() {
        let block = SpriteGrid(Array(repeating: "sssss", count: 5))
        let px = AutoShader.shade(block, ramps: ["s": ramp], fixed: [:])
        XCTAssertEqual(px.count, 25)
        XCTAssertEqual(color(px, 4, 2), ramp[0], "right edge → outline")
        XCTAssertEqual(color(px, 2, 4), ramp[0], "bottom edge → outline")
        XCTAssertEqual(color(px, 0, 2), ramp[1], "left edge → soft lit edge")
        XCTAssertEqual(color(px, 2, 0), ramp[1], "top edge → soft lit edge")
        XCTAssertEqual(color(px, 1, 1), ramp[3], "just inside the lit corner → moon rim")
        XCTAssertEqual(color(px, 2, 2), ramp[2], "centre → base")
        XCTAssertEqual(color(px, 3, 3), ramp[1], "near the shadow side → core shadow")
    }

    func testIsolatedPixelIsOutline() {
        let px = AutoShader.shade(SpriteGrid(["s"]), ramps: ["s": ramp], fixed: [:])
        XCTAssertEqual(px, [ShadedPixel(x: 0, y: 0, color: ramp[0])])
    }

    func testFixedColoursAreNotShaded() {
        let px = AutoShader.shade(SpriteGrid(["W"]), ramps: [:], fixed: ["W": .white])
        XCTAssertEqual(px, [ShadedPixel(x: 0, y: 0, color: .white)])
    }

    func testUnknownCharactersAreSkipped() {
        XCTAssertTrue(AutoShader.shade(SpriteGrid(["z"]), ramps: ["s": ramp], fixed: [:]).isEmpty)
    }

    func testOcclusionUnderOtherMaterial() {
        // 's' pixel at (2,2) has a different material directly below it → core shadow.
        let lines = ["sssss", "sssss", "sssss", "ssbss", "sssss", "sssss"]
        let px = AutoShader.shade(SpriteGrid(lines), ramps: ["s": ramp, "b": ramp], fixed: [:])
        XCTAssertEqual(color(px, 2, 2), ramp[1])
    }
}
