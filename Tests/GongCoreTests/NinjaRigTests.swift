import XCTest
@testable import GongCore

final class NinjaRigTests: XCTestCase {
    let floor = 50.0

    private func canvas(_ pose: RigPose, facing: Double = 1, quarter: Int = 0, ground: Bool = false,
                        options: RigOptions = RigOptions()) -> PixelCanvas {
        var c = PixelCanvas(width: 80, height: 70)
        NinjaRig.render(pose, into: &c, x: 40, y: floor, facing: facing, options: options, quarterTurns: quarter, ground: ground)
        return c
    }

    /// Every grounded pose stands exactly on the floor: lowest pixel on the row above it, never below, never floating.
    func testGroundedPosesTouchTheFloor() {
        var poses: [(String, RigPose)] = [("crouch", RigPoses.crouch(0)), ("down", RigPoses.down())]
        for i in 0..<20 {
            let t = Double(i) / 20
            poses += [("idle \(t)", RigPoses.idle(t * 3)), ("run \(t)", RigPoses.run(t)), ("land \(t)", RigPoses.land(t)),
                      ("slide \(t)", RigPoses.slide(t)), ("strike \(t)", RigPoses.strike(t)), ("hurt \(t)", RigPoses.hurt(t)),
                      ("crouch \(t)", RigPoses.crouch(t * 3))]
        }
        for (name, pose) in poses {
            XCTAssertTrue(pose.grounded, name)
            for f in [1.0, -1.0] {
                XCTAssertEqual(canvas(pose, facing: f).lowestOpaqueRow, Int(floor) - 1, name)
            }
        }
    }

    func testLyingDownRestsOnTheFloor() {
        for q in [1, -1] {
            XCTAssertEqual(canvas(RigPoses.down(), quarter: q, ground: true).lowestOpaqueRow, Int(floor) - 1)
        }
    }

    func testCrouchAndSlideAreLow() {
        func height(_ p: RigPose) -> Int {
            let c = canvas(RigPose(lean: p.lean, frontLeg: p.frontLeg, backLeg: p.backLeg, frontArm: p.frontArm,
                                   backArm: p.backArm, staff: .none, grounded: true))
            let top = (0..<c.height).first { y in (0..<c.width).contains { c[$0, y].a > 0 } } ?? c.height
            return Int(floor) - top
        }
        let standing = height(RigPoses.idle(0))
        XCTAssertGreaterThanOrEqual(standing, 28)
        XCTAssertLessThanOrEqual(height(RigPoses.crouch(0)), 22)
        XCTAssertLessThanOrEqual(height(RigPoses.slide(0.5)), standing / 2, "slide is under half the standing height")
    }

    func testMirroringFlipsTheFigure() {
        let right = canvas(RigPoses.idle(0)), left = canvas(RigPoses.idle(0), facing: -1)
        XCTAssertNotEqual(right, left)
        // the staff knob (felt) sits in front: right of centre when facing right, left when facing left
        func feltX(_ c: PixelCanvas) -> [Int] { (0..<c.height).flatMap { y in (0..<c.width).filter { c[$0, y] == RetroPalette.felt[2] } } }
        XCTAssertTrue(feltX(right).allSatisfy { $0 > 40 })
        XCTAssertTrue(feltX(left).allSatisfy { $0 < 40 })
    }

    func testSaltoQuarterTurnsDiffer() {
        let frames = (0..<4).map { canvas(RigPoses.tuck(), quarter: $0) }
        XCTAssertEqual(Set(frames.map(\.pixels)).count, 4)
    }

    func testFlashAndDarken() {
        let normal = canvas(RigPoses.idle(0))
        let flash = canvas(RigPoses.idle(0), options: RigOptions(flash: true))
        XCTAssertTrue(flash.pixels.filter { $0.a > 0 }.allSatisfy { $0 == .white })
        let dark = canvas(RigPoses.idle(0), options: RigOptions(darken: 0.35))
        func lum(_ c: PixelCanvas) -> Int { c.pixels.reduce(0) { $0 + Int($1.r) + Int($1.g) + Int($1.b) } }
        XCTAssertLessThan(lum(dark), lum(normal))
    }

    func testDeterministic() {
        XCTAssertEqual(canvas(RigPoses.run(0.3)), canvas(RigPoses.run(0.3)))
    }

    /// Game over: flat on his back — wider than tall, face (eye whites) up on top, legs out to the side.
    func testLyingDownIsOnHisBack() {
        for f in [1.0, -1.0] {
            var c = PixelCanvas(width: 80, height: 70)
            NinjaRig.render(RigPoses.down(), into: &c, x: 40, y: floor, facing: f, quarterTurns: -Int(f), ground: true)
            let pts = (0..<c.height).flatMap { y in (0..<c.width).compactMap { x in c[x, y].a > 0 ? (x, y) : nil } }
            let xs = pts.map(\.0), ys = pts.map(\.1)
            let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
            XCTAssertGreaterThan(w, h * 2, "lying flat")
            let eyes = pts.filter { c[$0.0, $0.1] == .white }.map(\.1)
            XCTAssertFalse(eyes.isEmpty)
            XCTAssertLessThan(Double(eyes.reduce(0, +)) / Double(eyes.count), Double(ys.min()! + ys.max()!) / 2, "face up")
        }
    }

    /// On his back means head, back and legs all rest on the floor: the bottom row is covered along most of the body.
    func testLyingRestsOnTheWholeBack() {
        for f in [1.0, -1.0] {
            var c = PixelCanvas(width: 80, height: 70)
            NinjaRig.render(RigPoses.down(), into: &c, x: 40, y: floor, facing: f, quarterTurns: -Int(f), ground: true)
            let xs = (0..<c.height).flatMap { y in (0..<c.width).filter { c[$0, y].a > 0 } }
            let length = xs.max()! - xs.min()! + 1
            // the two rows just above the floor (outline + one row of body); neck and knees leave natural gaps
            let touching = Set((Int(floor) - 2..<Int(floor)).flatMap { y in (0..<c.width).filter { c[$0, y].a > 0 } })
            XCTAssertGreaterThan(Double(touching.count), Double(length) * 0.65, "lies on head, back and legs (facing \(f))")
        }
    }
}
