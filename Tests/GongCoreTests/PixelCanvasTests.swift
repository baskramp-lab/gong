import XCTest
@testable import GongCore

final class PixelCanvasTests: XCTestCase {
    let red = RGBA(hex: 0xFF0000)
    let blue = RGBA(hex: 0x0000FF)

    func testHexInit() {
        XCTAssertEqual(RGBA(hex: 0x3D2F78), RGBA(r: 0x3D, g: 0x2F, b: 0x78, a: 255))
    }

    func testSetAndOutOfBounds() {
        var c = PixelCanvas(width: 4, height: 3)
        c.set(1, 2, red)
        c.set(-1, 0, red)
        c.set(4, 0, red)
        c.set(0, 3, red)
        XCTAssertEqual(c[1, 2], red)
        XCTAssertEqual(c[9, 9], .clear)
        XCTAssertEqual(c.pixels.filter { $0 == red }.count, 1)
    }

    func testFractionalCoordinatesRound() {
        var c = PixelCanvas(width: 4, height: 4)
        c.set(1.6, 0.4, red)
        XCTAssertEqual(c[2, 0], red)
    }

    func testAlphaBlendOverOpaque() {
        var c = PixelCanvas(width: 1, height: 1, fill: blue)
        c.set(0, 0, red, alpha: 0.25)
        XCTAssertEqual(c[0, 0], RGBA(r: 64, g: 0, b: 191, a: 255))
    }

    func testAlphaBlendOverClear() {
        var c = PixelCanvas(width: 1, height: 1)
        c.set(0, 0, red, alpha: 0.5)
        XCTAssertEqual(c[0, 0].a, 128)
        XCTAssertEqual(c[0, 0].r, 255)
    }

    func testFillRect() {
        var c = PixelCanvas(width: 5, height: 5)
        c.fillRect(x: 1, y: 1, w: 2, h: 3, red)
        XCTAssertEqual(c.pixels.filter { $0 == red }.count, 6)
        XCTAssertEqual(c[2, 3], red)
        XCTAssertEqual(c[3, 3], .clear)
    }

    func testLineHitsBothEndpoints() {
        var c = PixelCanvas(width: 10, height: 10)
        c.line(1, 1, 8, 5, red)
        XCTAssertEqual(c[1, 1], red)
        XCTAssertEqual(c[8, 5], red)
    }

    func testThickLineIsCentered() {
        var c = PixelCanvas(width: 10, height: 10)
        c.line(5, 5, 5, 5, red, thickness: 3)
        XCTAssertEqual(c.pixels.filter { $0 == red }.count, 9)
        XCTAssertEqual(c[4, 4], red)
        XCTAssertEqual(c[6, 6], red)
    }

    func testDrawCompositesNonTransparent() {
        var dst = PixelCanvas(width: 3, height: 3, fill: blue)
        var src = PixelCanvas(width: 2, height: 2)
        src.set(1, 1, red)
        dst.draw(src, x: 1, y: 1)
        XCTAssertEqual(dst[2, 2], red)
        XCTAssertEqual(dst[1, 1], blue)
    }

    func testShiftedRepeatsEdge() {
        var c = PixelCanvas(width: 3, height: 1)
        c.set(0, 0, red); c.set(1, 0, blue); c.set(2, 0, blue)
        let s = c.shifted(dx: 1, dy: 0)
        XCTAssertEqual(s[0, 0], red)
        XCTAssertEqual(s[1, 0], red)
        XCTAssertEqual(s[2, 0], blue)
    }

    func testScaledUpIsNearestNeighbor() {
        var c = PixelCanvas(width: 2, height: 1)
        c.set(0, 0, red); c.set(1, 0, blue)
        let s = c.scaled(to: 4)
        XCTAssertEqual(s.width, 4); XCTAssertEqual(s.height, 2)
        XCTAssertEqual(s[1, 1], red)
        XCTAssertEqual(s[2, 0], blue)
    }

    func testScaledDownAverages() {
        var c = PixelCanvas(width: 2, height: 2)
        c.fillRect(x: 0, y: 0, w: 1, h: 2, RGBA(hex: 0xFFFFFF))
        c.fillRect(x: 1, y: 0, w: 1, h: 2, RGBA(hex: 0x000000))
        let s = c.scaled(to: 1)
        XCTAssertEqual(s[0, 0], RGBA(r: 128, g: 128, b: 128, a: 255))
    }

    func testCGImage() throws {
        let img = try XCTUnwrap(PixelCanvas(width: 7, height: 5, fill: red).cgImage())
        XCTAssertEqual(img.width, 7)
        XCTAssertEqual(img.height, 5)
    }

    func testRotatedQuarterTurns() {
        var c = PixelCanvas(width: 3, height: 2)
        c.set(0, 0, .white)                          // top-left
        let cw = c.rotated(quarterTurns: 1)          // clockwise: top-left → top-right
        XCTAssertEqual(cw.width, 2); XCTAssertEqual(cw.height, 3)
        XCTAssertEqual(cw[1, 0], .white)
        XCTAssertEqual(c.rotated(quarterTurns: 2)[2, 1], .white)
        XCTAssertEqual(c.rotated(quarterTurns: -1)[0, 2], .white)
        XCTAssertEqual(c.rotated(quarterTurns: 4), c)
    }

    func testCroppedKeepsLeftColumns() {
        var c = PixelCanvas(width: 5, height: 2)
        c.set(1, 1, .white); c.set(4, 0, .white)
        let k = c.cropped(width: 3)
        XCTAssertEqual(k.width, 3); XCTAssertEqual(k.height, 2)
        XCTAssertEqual(k[1, 1], .white)
        XCTAssertEqual(k.pixels.filter { $0 == .white }.count, 1)
    }

    func testLowestOpaqueRow() {
        var c = PixelCanvas(width: 4, height: 6)
        XCTAssertNil(c.lowestOpaqueRow)
        c.set(2, 1, .white); c.set(0, 4, .white)
        XCTAssertEqual(c.lowestOpaqueRow, 4)
    }
}
