import XCTest
@testable import GongCore

final class SceneRendererTests: XCTestCase {
    let layout = SceneLayout.modal

    private func frame(_ cycle: Double, renderer: SceneRenderer = SceneRenderer()) -> PixelCanvas {
        renderer.render(StrikeTimeline.state(cycleTime: cycle, time: cycle, reduceMotion: false, layout: layout))
    }

    func testRendersWholeCycle() {
        let r = SceneRenderer()
        for i in 0..<(20 * 30) {
            let c = frame(Double(i) / 30, renderer: r)
            XCTAssertEqual(c.width, 100); XCTAssertEqual(c.height, 92)
        }
    }

    func testEveryPixelIsOpaque() {
        let c = frame(5)
        XCTAssertTrue(c.pixels.allSatisfy { $0.a == 255 })
    }

    func testGongCentreIsBrassThenFlashes() {
        XCTAssertEqual(frame(5)[layout.gongX, layout.gongY], RetroPalette.brass[5])
        XCTAssertEqual(frame(0.86)[layout.gongX, layout.gongY], .white)
    }

    func testHitFrameDiffersFromIdle() {
        XCTAssertNotEqual(frame(5), frame(1.0))
    }

    func testDeterministic() {
        XCTAssertEqual(frame(0.6), frame(0.6))
    }

    func testNinjaIsVisibleAtHome() {
        // suit colours inside the ninja's bounding box at home position
        let c = frame(5)
        let suit = Set(RetroPalette.suit)
        let hits = (0..<20).flatMap { x in (0..<32).map { y in c[Int(layout.homeX) + x, layout.floorY + y] } }.filter(suit.contains)
        XCTAssertGreaterThan(hits.count, 150)
    }

    func testAppIcon() {
        let icon = SceneRenderer.appIcon()
        XCTAssertEqual(icon.width, 64); XCTAssertEqual(icon.height, 64)
        for (x, y) in [(0, 0), (63, 0), (0, 63), (63, 63), (5, 5)] { XCTAssertEqual(icon[x, y].a, 0, "(\(x),\(y))") }
        XCTAssertEqual(icon[36, 32].a, 255)
        XCTAssertEqual(icon[32, 4].a, 255)
    }

    func testMiniGongFitsItsCanvas() {
        let c = SceneRenderer.miniGong()
        XCTAssertEqual(c.width, 52); XCTAssertEqual(c.height, 56)
        XCTAssertEqual(c[26, 26], RetroPalette.brass[5], "boss at the centre")
        XCTAssertEqual(c[0, 0], .clear, "transparent background")
        let used = (0..<56).flatMap { y in (0..<52).map { x in c[x, y] } }.filter { $0.a > 0 }.count
        XCTAssertGreaterThan(used, 400)
    }

    func testWorldBackgroundStartsWithTheSceneBackdrop() {
        let world = SceneRenderer.worldBackground()
        XCTAssertEqual(world.width, SceneRenderer.worldWidth); XCTAssertEqual(world.height, layout.height)
        XCTAssertEqual(world.cropped(width: layout.width), SceneRenderer.background(width: layout.width, height: layout.height))
        XCTAssertTrue(world.pixels.allSatisfy { $0.a == 255 })
    }

    func testTakeOffDrawsTheGameNinja() {
        let st = StrikeTimeline.state(cycleTime: 0.55, time: 0.55, reduceMotion: false, layout: layout)
        let rig = SceneRenderer().render(st)
        var noRig = st; noRig.rigJump = nil
        XCTAssertNotEqual(rig, SceneRenderer().render(noRig))
    }
}
