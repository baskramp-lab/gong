import XCTest
@testable import GongCore

final class GameRendererTests: XCTestCase {
    func testCanvasSize() {
        let c = GameRenderer().render(NinjaGame(seed: 1), time: 0)
        XCTAssertEqual(c.width, 228); XCTAssertEqual(c.height, 92)
    }

    func testDrawsShuriken() {
        var g = NinjaGame(seed: 1)
        g.spawn(Shuriken(x: 30, y: 40, vx: 0, lane: .high))
        let c = GameRenderer().render(g, time: 0)
        XCTAssertEqual(c[30, 40], RetroPalette.steelDark, "hub")
    }

    func testHeartsMatchLives() {
        let r = GameRenderer()
        var g = NinjaGame(seed: 1)
        func full(_ c: PixelCanvas, _ i: Int) -> Bool {
            let o = GameRenderer.heartOrigin(index: i)
            return c[o.x + 1, o.y + 1] == RetroPalette.heart
        }
        var c = r.render(g, time: 0)
        XCTAssertTrue((0..<3).allSatisfy { full(c, $0) })
        g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
        g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60)
        c = r.render(g, time: 0)
        XCTAssertEqual((0..<3).filter { full(c, $0) }.count, 2)
    }

    func testMirrorsWhenFacingLeft() {
        let r = GameRenderer()
        let right = r.render(NinjaGame(seed: 1), time: 0)
        var g = NinjaGame(seed: 1)
        g.step(dt: 1.0 / 60, input: GameInput(left: true), minutesToStart: 60)
        g.step(dt: 0, input: GameInput(), minutesToStart: 60)
        let left = r.render(g, time: 0)
        XCTAssertNotEqual(right, left)
    }

    func testGameOverText() {
        var g = NinjaGame(seed: 1)
        for _ in 0..<3 {
            g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
            for _ in 0..<80 { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60) }
        }
        XCTAssertEqual(g.phase, .gameOver)
        let r = GameRenderer()
        func golds(_ c: PixelCanvas) -> Int {   // the text band above the gong's top
            (22..<36).reduce(0) { n, y in n + (0..<NinjaGame.width).filter { c[$0, y] == RetroPalette.gold }.count }
        }
        XCTAssertGreaterThan(golds(r.render(g, time: 0)) - golds(r.render(NinjaGame(seed: 1), time: 0)), 60, "GAME OVER drawn in gold")
    }

    func testGameOverCardReplacesTheClock() {
        var g = NinjaGame(seed: 1)
        for _ in 0..<3 {
            g.spawn(Shuriken(x: g.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
            for _ in 0..<80 { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60) }
        }
        let r = GameRenderer()
        let a = r.render(g, time: 0, secondsToStart: 161), b = r.render(g, time: 0, secondsToStart: 100)
        XCTAssertEqual(a, b, "no countdown on the game-over screen")
        let k = GameRenderer.gameOverLayout(title: "GAME OVER", tagline: "BETTER LUCK NEXT MEETING", score: "SCORE 0   HI 0")
        XCTAssertEqual([k.x, k.y, k.w, k.h], [32, 13, 164, 47], "English card size")
        XCTAssertEqual(a[k.x, k.y + k.h / 2], RetroPalette.brass[3], "gold card frame")
        XCTAssertEqual(a[k.x + 3, k.y + k.h - 4], GameRenderer.cardFill, "card fill")
    }

    func testGameOverTitleDropsInAndSettles() {
        XCTAssertEqual(GameRenderer.dropOffset(since: 0), -40)
        XCTAssertLessThan(GameRenderer.dropOffset(since: 0.36), 0, "bounce")
        XCTAssertEqual(GameRenderer.dropOffset(since: 0.5), 0)
        XCTAssertEqual(GameRenderer.dropOffset(since: 5), 0)
    }

    /// After game over the ninja falls, tumbles and then lies *on* the floor — drawn, and not floating.
    func testGameOverNinjaLiesOnTheFloor() {
        var g = NinjaGame(seed: 1)
        g.autoSpawn = false
        g.step(dt: 1.0 / 60, input: GameInput(jump: true), minutesToStart: 60)   // die in the air
        for _ in 0..<3 {
            g.spawn(Shuriken(x: g.x + 10, y: g.y + 15, vx: 1, lane: .high))
            for _ in 0..<80 where g.phase == .playing { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60) }
        }
        XCTAssertEqual(g.phase, .gameOver)
        for _ in 0..<150 { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60) }
        let layout = SceneLayout.modal
        var bare = SceneRenderer.worldBackground()
        SceneRenderer.petals(&bare, time: 0)
        SceneRenderer.gong(&bare, cx: layout.gongX, cy: layout.gongY, r: layout.gongRadius, shake: 0, flash: false)
        bare.fillRect(x: 0, y: 0, w: bare.width, h: bare.height, RetroPalette.ink, alpha: GameRenderer.dim)   // game over dims the world
        let c = GameRenderer().render(g, time: 0)
        let floorRow = NinjaGame.height - 6
        var drawn = 0, lowest = 0
        for y in 50..<NinjaGame.height {
            for x in max(0, Int(g.x) - 15)..<min(NinjaGame.width, Int(g.x) + 35) where c[x, y] != bare[x, y] {
                drawn += 1; lowest = max(lowest, y)
            }
        }
        XCTAssertGreaterThan(drawn, 40, "ninja drawn on the game-over screen")
        XCTAssertEqual(lowest, floorRow - 1, "lying on the floor, not floating and not sunk into it")
    }

    func testReduceMotionInvulnerableIsDarkerNotTranslucent() {
        let r = GameRenderer()
        let fresh = NinjaGame(seed: 1)
        var hit = fresh
        hit.autoSpawn = false
        hit.spawn(Shuriken(x: hit.x + 5, y: NinjaGame.highY, vx: 1, lane: .high))
        hit.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60)
        XCTAssertGreaterThan(hit.invulnerable, 0)
        // Advance to a frame where the normal render is not in a blink-off phase.
        while Int((hit.invulnerable * 10).rounded(.down)) % 2 == 1 {
            hit.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60)
        }
        XCTAssertGreaterThan(hit.invulnerable, 0)
        let dark = r.render(hit, time: 0, reduceMotion: true)
        let normal = r.render(hit, time: 0, reduceMotion: false)
        func sum(_ p: RGBA) -> Int { Int(p.r) + Int(p.g) + Int(p.b) }
        var drawn = 0, darker = 0
        for yy in 0..<NinjaGame.spriteHeight {
            for xx in 0..<NinjaGame.spriteWidth {
                let x = Int(hit.x) + xx, y = Int(hit.y) + yy
                if dark[x, y] != normal[x, y] { drawn += 1; if sum(dark[x, y]) < sum(normal[x, y]) { darker += 1 } }
            }
        }
        XCTAssertGreaterThan(drawn, 20, "ninja still drawn")
        // Pixels already darker than ink (outline) may get marginally lighter; the bulk must darken.
        XCTAssertGreaterThan(darker * 4, drawn * 3, "ninja tinted darker, not ghosted")
    }

    /// Scene → game is seamless: with the same petal time, the world's left part shows the scene's backdrop,
    /// gong and petals pixel for pixel (only the ninja differs).
    func testWorldLeftPartMatchesTheScene() {
        let layout = SceneLayout.modal
        var g = NinjaGame(seed: 1, x: 150)   // ninja out of the scene part
        g.autoSpawn = false
        let world = GameRenderer().render(g, time: 0, petalTime: 3.3).cropped(width: layout.width)
        var scene = SceneRenderer.background(width: layout.width, height: layout.height)
        SceneRenderer.petals(&scene, time: 3.3)
        SceneRenderer.gong(&scene, cx: layout.gongX, cy: layout.gongY, r: layout.gongRadius, shake: 0, flash: false)
        var differ = 0
        for y in 0..<layout.height { for x in 0..<layout.width where world[x, y] != scene[x, y] { differ += 1 } }
        // hearts are drawn in the game only
        XCTAssertLessThanOrEqual(differ, 3 * 17, "only the hearts differ")
    }

    func testCountdownAndScoreTopRight() {
        XCTAssertEqual(GameRenderer.clock(83.9), "1:23")
        XCTAssertEqual(GameRenderer.clock(5), "0:05")
        var g = NinjaGame(seed: 1)
        g.autoSpawn = false
        func region(_ c: PixelCanvas) -> [RGBA] { (3..<38).flatMap { y in ((NinjaGame.width - 60)..<NinjaGame.width).map { c[$0, y] } } }
        let r = GameRenderer()
        XCTAssertTrue(region(r.render(g, time: 0, secondsToStart: 161)).contains(RetroPalette.gold), "countdown in gold")
        XCTAssertNotEqual(region(r.render(g, time: 0, secondsToStart: 161)), region(r.render(g, time: 0, secondsToStart: 100)),
                          "the countdown ticks down")
        let before = region(r.render(g, time: 0))
        for _ in 0..<(60 * 12) { g.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 60) }
        XCTAssertEqual(g.score, 120)
        XCTAssertNotEqual(before, region(r.render(g, time: 0)), "score 0 → 120")
    }

    func testGameOverCardMakesRoomForAccentsAndLongLines() {
        let plain = GameRenderer.gameOverLayout(title: "GAME OVER", tagline: "BETTER LUCK NEXT MEETING", score: "SCORE 1")
        let accents = GameRenderer.gameOverLayout(title: "OYUN BİTTİ", tagline: "PRÓXIMA REUNIÃO", score: "PONTUAÇÃO 1")
        XCTAssertGreaterThan(accents.titleY, plain.titleY, "room for the dot above İ")
        XCTAssertGreaterThan(accents.h, plain.h)
        let long = GameRenderer.gameOverLayout(title: "PELI PÄÄTTYI NYT!", tagline: String(repeating: "W", count: 34), score: "X")
        XCTAssertLessThanOrEqual(long.x + long.w, NinjaGame.width - 4)
        XCTAssertGreaterThanOrEqual(long.w, PixelFont.width(of: String(repeating: "W", count: 34), scale: 1))
    }

    func testAccentedCapitalsDrawBaseAndMark() {
        XCTAssertTrue(PixelFont.canDraw("ÅÄÖ ØÆ ŁĄĘŚŻŹĆŃÓ ÇÉÈÊ ÑÃÕ ČŘŠŽŐŰ ŞĞİ ĂȘȚ"))
        func ink(_ s: String) -> Int {
            var c = PixelCanvas(width: 20, height: 20)
            PixelFont.draw(s, into: &c, x: 2, y: 5, scale: 1, color: .white)
            return c.pixels.filter { $0 == .white }.count
        }
        XCTAssertGreaterThan(ink("É"), ink("E"), "acute above")
        XCTAssertGreaterThan(ink("Ç"), ink("C"), "cedilla below")
        XCTAssertEqual(PixelFont.extents(of: "É").above, 3)
        XCTAssertEqual(PixelFont.extents(of: "Ą").below, 2)
    }
}
