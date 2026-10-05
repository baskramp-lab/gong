import Foundation

/// Draws a `NinjaGame` into the 228×92 world in the scene's 16-bit style: same backdrop, petals and gong as the
/// modal scene (which is the world's left part), with the articulated `NinjaRig` ninja.
public final class GameRenderer {
    private lazy var backdrop = SceneRenderer.worldBackground()
    private let layout = SceneLayout.modal

    public init() {}

    /// Spinning 7×7 star, two frames (+ and ×), drawn with an ink outline so it reads against the sky. `o` = hub.
    static let shurikenFrames = [
        ["...#...", "...#...", "..###..", "###o###", "..###..", "...#...", "...#..."],
        ["#.....#", ".#...#.", "..###..", "..#o#..", "..###..", ".#...#.", "#.....#"],
    ]

    public static func heartOrigin(index i: Int) -> (x: Int, y: Int) { (3 + i * 7, 3) }
    static let heartRows = [".#.#.", "#####", "#####", ".###.", "..#.."]

    /// `petalTime` is the scene clock's time, so the blossom carries on unbroken from the scene into the game.
    public func render(_ g: NinjaGame, time t: Double, shake: Int = 0, newHigh: Bool = false,
                       reduceMotion: Bool = false, petalTime: Double? = nil, best: Int = 0,
                       score: Int? = nil, secondsToStart: Double? = nil) -> PixelCanvas {
        var c = backdrop
        SceneRenderer.petals(&c, time: petalTime ?? t, tileWidth: layout.width)

        // the gong is scenery; it rings once more at game over
        let over = g.phase == .gameOver
        let since = over ? g.deathTime : -1
        let ring = !reduceMotion && since > 0.05 ? sin(since * 40) * 3 * exp(-since * 2) : 0
        SceneRenderer.gong(&c, cx: layout.gongX, cy: layout.gongY, r: layout.gongRadius, shake: ring,
                           flash: !reduceMotion && since >= 0 && since < 0.1)
        if since > 0.08 && since < 1.1 { gongText(&c, since: since) }

        let frame = Int((max(0, t) * 20).rounded(.down)) % 2
        for s in g.shurikens { drawShuriken(&c, s, frame: frame) }
        dust(&c, g, time: t)
        drawNinja(&c, g, time: t, reduceMotion: reduceMotion)

        for p in g.pops { shadowed(&c, "+\(NinjaGame.deflectPoints)", x: Int(p.x.rounded()) - 8, y: Int(p.y.rounded()) - 10, scale: 1, color: RetroPalette.gold) }
        let points = score ?? g.score
        if over {
            // the world dims after the gong; the hearts stay, the clock makes way for the card
            c.fillRect(x: 0, y: 0, w: c.width, h: c.height, RetroPalette.ink, alpha: Self.dim * min(1, max(0, since) / 0.3))
        } else {
            drawClock(&c, secondsToStart: secondsToStart, score: points, best: max(best, points))
        }
        for i in 0..<NinjaGame.maxLives { drawHeart(&c, index: i, full: i < g.lives) }
        if over {
            drawGameOver(&c, since: since, score: points, best: max(best, points), newHigh: newHigh, reduceMotion: reduceMotion)
        }
        if shake != 0 && !reduceMotion { c = c.shifted(dx: shake, dy: 1) }
        return c
    }

    // MARK: - Game over

    static let dim = 0.45
    static let cardFill = RGBA(hex: 0x1B1A2E)

    /// Where the game-over card and its three lines go. Grows with long translations and with accents above
    /// or below a line; in English it is 164×47 at (32, 13).
    struct GameOverLayout: Equatable {
        var x, y, w, h: Int
        var titleScale: Int
        /// Line tops relative to the card.
        var titleY, taglineY, scoreY: Int
    }

    static func gameOverLayout(title: String, tagline: String, score: String) -> GameOverLayout {
        let maxW = NinjaGame.width - 8, pad = 14
        let scale = PixelFont.width(of: title, scale: 2) + pad <= maxW ? 2 : 1
        let t = PixelFont.extents(of: title), g = PixelFont.extents(of: tagline), s = PixelFont.extents(of: score)
        let titleY = 6 + t.above * scale
        let taglineY = titleY + PixelFont.glyphHeight * scale + t.below * scale + 4 + g.above
        let scoreY = taglineY + PixelFont.glyphHeight + g.below + 4 + s.above
        let h = scoreY + PixelFont.glyphHeight + s.below + 5
        let text = max(PixelFont.width(of: title, scale: scale), PixelFont.width(of: tagline, scale: 1), PixelFont.width(of: score, scale: 1))
        let w = min(maxW, max(164, text + pad))
        let x = (NinjaGame.width - w) / 2
        // A wide card reaches the hearts' column: keep it below them.
        let hearts = heartOrigin(index: NinjaGame.maxLives - 1)
        let top = x - 1 <= hearts.x + 5 ? hearts.y + 7 : 3
        return GameOverLayout(x: x, y: max(top, 60 - h), w: w, h: h,
                              titleScale: scale, titleY: titleY, taglineY: taglineY, scoreY: scoreY)
    }

    /// GAME OVER drops in on the gong and bounces once; tagline; score and record (or a blinking new record).
    private func drawGameOver(_ c: inout PixelCanvas, since: Double, score: Int, best: Int, newHigh: Bool, reduceMotion: Bool) {
        let title = L("GAME OVER"), tagline = L("BETTER LUCK NEXT MEETING")
        let scoreLine = newHigh ? L("NEW HIGH SCORE! %d", score) : L("SCORE %1$d   HI %2$d", score, best)
        let k = Self.gameOverLayout(title: title, tagline: tagline, score: scoreLine)
        c.fillRect(x: k.x - 1, y: k.y - 1, w: k.w + 2, h: k.h + 2, RetroPalette.ink)
        c.fillRect(x: k.x, y: k.y, w: k.w, h: k.h, RetroPalette.brass[3])
        c.fillRect(x: k.x + 1, y: k.y + 1, w: k.w - 2, h: k.h - 2, RetroPalette.ink)
        c.fillRect(x: k.x + 2, y: k.y + 2, w: k.w - 4, h: k.h - 4, Self.cardFill)

        let tx = (NinjaGame.width - PixelFont.width(of: title, scale: k.titleScale)) / 2
        let ty = k.y + k.titleY + (reduceMotion ? 0 : Self.dropOffset(since: since))
        PixelFont.draw(title, into: &c, x: tx + 1, y: ty + 1, scale: k.titleScale, color: RetroPalette.ink)
        PixelFont.draw(title, into: &c, x: tx, y: ty, scale: k.titleScale, color: RetroPalette.gold, lower: RetroPalette.brass[3])

        centred(&c, tagline, y: k.y + k.taglineY, scale: 1, color: RetroPalette.light)
        if newHigh {
            let blink = !reduceMotion && Int((since * 4).rounded(.down)) % 2 == 1
            centred(&c, scoreLine, y: k.y + k.scoreY, scale: 1, color: blink ? RetroPalette.light : RetroPalette.gold)
            sparkles(&c, around: k, time: since, reduceMotion: reduceMotion)
        } else {
            centred(&c, scoreLine, y: k.y + k.scoreY, scale: 1, color: RetroPalette.starDim)
        }
    }

    /// Pixels above the resting spot: falls in 0.25 s from 40 px up, then one 2 px bounce.
    static func dropOffset(since: Double) -> Int {
        let u = min(1, max(0, (since - 0.05) / 0.25))
        if u < 1 { return -Int((pow(1 - u, 2) * 40).rounded()) }
        let b = (since - 0.3) / 0.12
        return b < 1 ? -Int((sin(b * .pi) * 2).rounded()) : 0
    }

    private func sparkles(_ c: inout PixelCanvas, around k: GameOverLayout, time t: Double, reduceMotion: Bool) {
        let spots = [(k.x - 4, k.y + 6), (k.x + k.w + 3, k.y + 14), (k.x + 8, k.y + k.h + 3), (k.x + k.w - 10, k.y - 4),
                     (k.x - 3, k.y + k.h - 8)]
        for (i, (x, y)) in spots.enumerated() {
            let size = reduceMotion ? 1 : (Int((t * 6).rounded(.down)) + i) % 3
            c.set(x, y, RetroPalette.light)
            guard size > 0 else { continue }
            for d in 1...size {
                for (dx, dy) in [(d, 0), (-d, 0), (0, d), (0, -d)] { c.set(x + dx, y + dy, d == size ? RetroPalette.gold : RetroPalette.light) }
            }
        }
    }

    // MARK: - Ninja

    /// The pose for the game state, as in the prototype: death tumble → lying, hurt, slide, strike, salto,
    /// landing, crouch, run, idle.
    func drawNinja(_ c: inout PixelCanvas, _ g: NinjaGame, time t: Double, reduceMotion: Bool) {
        let f: Double = g.facing == .right ? 1 : -1
        let fx = g.x + Double(NinjaGame.spriteWidth) / 2, fy = g.y + Double(NinjaGame.spriteHeight)
        let over = g.phase == .gameOver
        let sinceHit = g.invulnerable > 0 ? NinjaGame.invulnerableDuration - g.invulnerable : 9
        if !over && !reduceMotion && g.invulnerable > 0 && Int((g.invulnerable * 10).rounded(.down)) % 2 == 1 { return }

        var pose: RigPose, quarter = 0, ground = false, lift = 0.0
        var opts = RigOptions(time: t, speed: g.isSliding ? NinjaGame.slideSpeed : Double(abs(g.walkDirection)) * NinjaGame.walkSpeed + abs(g.vy) / 3,
                              blink: t.truncatingRemainder(dividingBy: 3.1) < 0.12)
        if over {
            if g.isAirborne || g.deathTime < 0.1 {
                pose = RigPoses.tuck(); quarter = reduceMotion ? 0 : Int(f) * (Int(g.deathTime * 10) % 4)
            } else {
                pose = RigPoses.down(); quarter = -Int(f); ground = true
            }
        } else if sinceHit < 0.35 {
            pose = RigPoses.hurt(sinceHit / 0.35)
            opts.flash = sinceHit < 0.06 && !reduceMotion
        } else if g.isSliding {
            pose = RigPoses.slide(1 - g.slideTimer / NinjaGame.slideDuration)
        } else if g.isStriking {
            let u = 1 - g.strikeTimer / NinjaGame.strikeDuration
            pose = RigPoses.strike(u)
            if g.isAirborne { pose.grounded = false; pose.lift = 2; pose.frontLeg = .init(1.2, 0.1); pose.backLeg = .init(0.4, -0.5) }
            if u > 0.25 && u < 0.7 {
                opts.smear = (0..<3).compactMap { i in
                    RigPoses.strike(max(0.22, u - 0.06 * Double(i + 1))).staffAngle.map { RigOptions.Smear(angle: $0, alpha: 0.5 - Double(i) * 0.15) }
                }
            }
        } else if g.isAirborne {
            let u = min(max((g.vy + NinjaGame.jumpSpeed) / (2 * NinjaGame.jumpSpeed), 0), 1)   // 0 take-off → 1 landing
            if u < 0.12 || u > 0.9 || reduceMotion {
                pose = u < 0.12 || u > 0.9 ? RigPoses.jump(vy: g.vy) : RigPoses.tuck()
            } else {
                pose = RigPoses.tuck(); quarter = Int(f) * (Int(((u - 0.12) / 0.78 * 4).rounded(.down)) + 1); lift = -6
            }
        } else if g.sinceLanding < 0.14 {
            pose = RigPoses.land(g.sinceLanding / 0.14)
        } else if g.isCrouching {
            pose = RigPoses.crouch(t)
        } else if g.walkDirection != 0 {
            pose = RigPoses.run(t)
        } else {
            pose = RigPoses.idle(t)
        }
        if reduceMotion && g.invulnerable > 0 && !over { opts.darken = 0.35 }
        NinjaRig.render(pose, into: &c, x: fx, y: fy + lift, facing: f, options: opts, quarterTurns: quarter, ground: ground)
    }

    /// Kicked-up floor dust behind a slide and around a landing (deterministic from time).
    private func dust(_ c: inout PixelCanvas, _ g: NinjaGame, time t: Double) {
        let fx = g.x + Double(NinjaGame.spriteWidth) / 2, floor = Double(NinjaGame.height - 6)
        let col = RGBA(hex: 0xF2D3A0)
        if g.isSliding {
            let back: Double = g.facing == .right ? -1 : 1
            for i in 0..<5 {
                let age = (t * 6 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                c.set(fx + back * (4 + Double(i) * 3 + age * 4), floor - 1 - age * 4 - Double(i % 2), col, alpha: 1 - age)
            }
        }
        if g.sinceLanding < 0.3 {
            let age = g.sinceLanding / 0.3
            for i in 0..<4 {
                let side: Double = i % 2 == 0 ? -1 : 1
                c.set(fx + side * (3 + age * 6 + Double(i)), floor - 1 - age * 3, col, alpha: 1 - age)
            }
        }
    }

    private func gongText(_ c: inout PixelCanvas, since: Double) {
        let text = "GONG!", scale = 2
        let tw = PixelFont.width(of: text, scale: scale)
        let tx = layout.gongX - tw / 2, ty = max(1, layout.gongY - layout.gongRadius - 28)
        PixelFont.draw(text, into: &c, x: tx + 1, y: ty + 1, scale: scale, color: RetroPalette.ink)
        let flicker = Int((since * 10).rounded(.down)) % 2 == 1
        PixelFont.draw(text, into: &c, x: tx, y: ty, scale: scale, color: flicker ? RetroPalette.light : RetroPalette.gold)
    }

    /// Top right: the countdown to the meeting big in gold, score and record underneath.
    private func drawClock(_ c: inout PixelCanvas, secondsToStart: Double?, score: Int, best: Int) {
        var y = 3
        if let s = secondsToStart {
            let t = Self.clock(s.rounded(.up))
            shadowed(&c, t, x: NinjaGame.width - 3 - PixelFont.width(of: t, scale: 2), y: y, scale: 2, color: RetroPalette.gold)
            y += 17
        }
        for (text, col) in [(L("SCORE %d", score), RetroPalette.light), (L("HI %d", best), RetroPalette.starDim)] {
            let e = PixelFont.extents(of: text)
            y += e.above
            shadowed(&c, text, x: NinjaGame.width - 3 - PixelFont.width(of: text, scale: 1), y: y, scale: 1, color: col)
            y += 9 + e.below
        }
    }

    private func shadowed(_ c: inout PixelCanvas, _ text: String, x: Int, y: Int, scale: Int, color: RGBA) {
        PixelFont.draw(text, into: &c, x: x + 1, y: y + 1, scale: scale, color: RetroPalette.ink)
        PixelFont.draw(text, into: &c, x: x, y: y, scale: scale, color: color)
    }

    private func centred(_ c: inout PixelCanvas, _ text: String, y: Int, scale: Int, color: RGBA) {
        shadowed(&c, text, x: (NinjaGame.width - PixelFont.width(of: text, scale: scale)) / 2, y: y, scale: scale, color: color)
    }

    public static func clock(_ s: Double) -> String {
        let t = Int(max(0, s).rounded(.down))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    private func drawShuriken(_ c: inout PixelCanvas, _ s: Shuriken, frame: Int) {
        let rows = Self.shurikenFrames[frame].map { Array($0) }
        let ox = Int(s.x.rounded()) - 3, oy = Int(s.y.rounded()) - 3
        func solid(_ x: Int, _ y: Int) -> Bool { y >= 0 && y < rows.count && x >= 0 && x < rows[y].count && rows[y][x] != "." }
        for y in -1...rows.count { for x in -1...rows[0].count where !solid(x, y) {
            if solid(x - 1, y) || solid(x + 1, y) || solid(x, y - 1) || solid(x, y + 1) { c.set(ox + x, oy + y, RetroPalette.ink) }
        } }
        for (yy, row) in rows.enumerated() {
            for (xx, ch) in row.enumerated() where ch != "." {
                c.set(ox + xx, oy + yy, ch == "o" ? RetroPalette.steelDark : RetroPalette.steel)
            }
        }
    }

    private func drawHeart(_ c: inout PixelCanvas, index i: Int, full: Bool) {
        let o = Self.heartOrigin(index: i)
        for (yy, row) in Self.heartRows.enumerated() {
            for (xx, ch) in row.enumerated() where ch == "#" {
                c.set(o.x + xx, o.y + yy, full ? RetroPalette.heart : RetroPalette.heartEmpty)
            }
        }
    }
}
