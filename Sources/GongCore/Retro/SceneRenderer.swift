import Foundation

/// Draws a `SceneState` into a `PixelCanvas`. Keeps the static background and shaded sprites cached,
/// so a frame is mostly copying pixels.
public final class SceneRenderer {
    public let layout: SceneLayout
    private lazy var backdrop = SceneRenderer.background(width: layout.width, height: layout.height)
    private var sprites: [String: [ShadedPixel]] = [:]

    public init(layout: SceneLayout = .modal) { self.layout = layout }

    /// `petals: false` leaves the falling blossoms out (the browser preview draws them itself, continuously).
    public func render(_ s: SceneState, petals: Bool = true) -> PixelCanvas {
        var c = backdrop
        let r = layout.gongRadius, gx = Double(layout.gongX), gy = Double(layout.gongY)
        let t = s.time
        if petals { Self.petals(&c, time: t) }

        if let since = s.ringsTime {
            for k in 0..<3 {
                let u = since - 0.08 - Double(k) * 0.18
                guard u >= 0 else { continue }
                let rr = Double(r) + 3 + u * 40, alpha = max(0, 1 - u / 1.2)
                for a in stride(from: 0.0, to: 2 * Double.pi, by: 0.05) {
                    c.set(gx + cos(a) * rr, gy + sin(a) * rr * 0.85, RetroPalette.light, alpha: alpha)
                }
            }
        }
        Self.gong(&c, cx: layout.gongX, cy: layout.gongY, r: r, shake: s.gongShake, flash: s.gongFlash)

        let x = s.x, y = s.y
        if s.speedLines {
            for k in 0..<5 {
                let dk = Double(k)
                c.line(x - 14 - dk * 3, y + 8 + dk * 5, x - 4 - dk * 3, y + 8 + dk * 5, RetroPalette.light)
            }
        }
        if let u = s.rigJump {
            // take-off with the game's ninja (feet at the bottom centre of the 20×32 sprite box)
            let pose = RigPoses.jump(vy: u < 0.6 ? -100 : 0)
            for (k, g) in s.ghosts.enumerated() {
                NinjaRig.draw(pose, into: &c, x: g.x + 10, y: g.y + 32, facing: 1,
                              options: RigOptions(time: t, speed: 60, alpha: 0.3 - Double(k) * 0.08))
            }
            NinjaRig.draw(pose, into: &c, x: x + 10, y: y + 32, facing: 1, options: RigOptions(time: t, speed: 60))
            return finish(c, s)
        }
        for (k, g) in s.ghosts.enumerated() {
            blit(&c, sprite(.leap, blink: false, rotation: 0, sink: false), x: g.x, y: g.y, alpha: 0.3 - Double(k) * 0.08)
        }

        let shx = x + 12, shy = y + 14
        if case .swing(let angle, let length) = s.staff {
            mallet(&c, front: false, shx: shx, shy: shy, angle: angle, length: length)
        }
        blit(&c, sprite(s.pose, blink: s.blink, rotation: s.rotation, sink: s.sink), x: x, y: y)
        if s.rotation == 0 { headbandTails(&c, x: x, y: y, time: t, moving: s.isMoving) }
        if case .swing(let angle, let length) = s.staff {
            mallet(&c, front: true, shx: shx, shy: shy, angle: angle, length: length)
        }
        if case .guardStance(let angle) = s.staff { guardStaff(&c, x: x, y: y, sink: s.sink, angle: angle) }
        if s.smear {
            for k in 0..<3 {
                let yy = shy - 1 + Double(k)
                c.line(shx + 6, yy, gx - Double(r) * 0.45, yy, k == 1 ? .white : RetroPalette.gold)
            }
        }
        return finish(c, s)
    }

    /// Text burst and camera shake on top of the finished frame.
    private func finish(_ frame: PixelCanvas, _ s: SceneState) -> PixelCanvas {
        var c = frame
        let r = layout.gongRadius
        if let since = s.textTime {
            let text = "GONG!", scale = 2
            let tw = PixelFont.width(of: text, scale: scale)
            let tx = min(layout.width - tw - 3, layout.gongX - tw / 2), ty = max(1, layout.gongY - r - 28)
            PixelFont.draw(text, into: &c, x: tx + 1, y: ty + 1, scale: scale, color: RetroPalette.ink)
            let flicker = Int((since * 10).rounded(.down)) % 2 == 1
            PixelFont.draw(text, into: &c, x: tx, y: ty, scale: scale, color: flicker ? RetroPalette.light : RetroPalette.gold)
        }
        if s.cameraShake != 0 { c = c.shifted(dx: s.cameraShake, dy: 1) }
        return c
    }

    // MARK: - Ninja

    private func sprite(_ pose: NinjaPose, blink: Bool, rotation: Int, sink: Bool) -> [ShadedPixel] {
        let key = "\(pose.rawValue)|\(blink)|\(rotation)|\(sink)"
        if let hit = sprites[key] { return hit }
        let px = AutoShader.shade(NinjaSprites.grid(pose: pose, blink: blink, sink: sink, rotation: rotation),
                                  ramps: RetroPalette.ninjaRamps, fixed: RetroPalette.ninjaFixed)
        sprites[key] = px
        return px
    }

    private func blit(_ c: inout PixelCanvas, _ px: [ShadedPixel], x: Double, y: Double, alpha: Double = 1) {
        for p in px {
            c.set(Int((x + Double(p.x)).rounded(.towardZero)), Int((y + Double(p.y)).rounded(.towardZero)), p.color, alpha: alpha)
        }
    }

    private func headbandTails(_ c: inout PixelCanvas, x: Double, y: Double, time t: Double, moving: Bool) {
        let band = RetroPalette.headband
        for i in 1...8 {
            let di = Double(i)
            let wave = (sin(t * (moving ? 14 : 5) + di * 0.8) * (di / 8) * (moving ? 3 : 1.5)).rounded()
            let wy = wave + (moving ? 0 : (di / 4).rounded(.down))
            c.set(x + 2 - di, y + 4 + wy, i % 3 != 0 ? band[2] : band[3])
            c.set(x + 2 - di, y + 5 + wy, band[1])
        }
    }

    private func mallet(_ c: inout PixelCanvas, front: Bool, shx: Double, shy: Double, angle: Double, length: Double) {
        let behind = cos(angle) < -0.3 || sin(angle) < -0.6
        guard front != behind else { return }
        let hx = shx + cos(angle) * 6, hy = shy + sin(angle) * 6
        let mx = hx + cos(angle) * length, my = hy + sin(angle) * length
        Self.stick(&c, shx, shy, hx, hy, ramp: RetroPalette.suit, thickness: 3)
        Self.rod(&c, hx, hy, mx, my)
        c.fillRect(x: Int(hx.rounded()) - 1, y: Int(hy.rounded()) - 1, w: 3, h: 3, RetroPalette.skin[2])
        Self.knob(&c, mx, my)
    }

    private func guardStaff(_ c: inout PixelCanvas, x: Double, y: Double, sink: Bool, angle: Double) {
        let sy = sink ? 1.0 : 0.0, dx = cos(angle), dy = sin(angle)
        let h1x = x + 17, h1y = y + 15 + sy, h2x = h1x - dx * 5, h2y = h1y - dy * 5
        Self.rod(&c, h1x - dx * 9, h1y - dy * 9, h1x + dx * 14, h1y + dy * 14)
        Self.knob(&c, h1x + dx * 17, h1y + dy * 17)
        Self.stick(&c, x + 8, y + 13 + sy, h2x, h2y, ramp: RetroPalette.suit, thickness: 3)
        Self.stick(&c, x + 13, y + 13 + sy, h1x, h1y, ramp: RetroPalette.suit, thickness: 3)
        for (hx, hy) in [(h2x, h2y), (h1x, h1y)] {
            c.fillRect(x: Int(hx.rounded()) - 1, y: Int(hy.rounded()) - 1, w: 3, h: 3, RetroPalette.skin[2])
        }
        c.set(Int(h1x.rounded()) + 1, Int(h1y.rounded()) + 1, RetroPalette.skin[0])
    }

    // MARK: - Shared shapes

    /// Thin wooden staff: 1 px shaft with a dark line underneath.
    static func rod(_ c: inout PixelCanvas, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        c.line(x0 + 0.6, y0 + 1, x1 + 0.6, y1 + 1, RetroPalette.wood[0])
        c.line(x0, y0, x1, y1, RetroPalette.wood[2])
    }

    /// Shaded limb: outline, base and a 1 px highlight on the lit side.
    static func stick(_ c: inout PixelCanvas, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, ramp: [RGBA], thickness: Int) {
        let nx = -(y1 - y0), ny = x1 - x0
        let len = hypot(nx, ny) == 0 ? 1 : hypot(nx, ny)
        c.line(x0, y0, x1, y1, ramp[0], thickness: thickness + 2)
        c.line(x0, y0, x1, y1, ramp[2], thickness: thickness)
        c.line(x0 - nx / len * 0.8, y0 - ny / len * 0.8 - 0.5, x1 - nx / len * 0.8, y1 - ny / len * 0.8 - 0.5, ramp[3])
    }

    /// Round felt mallet head, lit from the upper-left.
    static func knob(_ c: inout PixelCanvas, _ x: Double, _ y: Double) {
        let f = RetroPalette.felt, mx = Int(x.rounded()), my = Int(y.rounded())
        for yy in -3...3 {
            for xx in -3...3 {
                let d = hypot(Double(xx), Double(yy))
                if d > 3.2 { continue }
                var col = d > 2.4 ? f[0] : f[2]
                if d <= 2.4 && xx + yy >= 2 { col = f[1] }
                if d <= 2.4 && Double((xx + 1) * (xx + 1) + (yy + 1) * (yy + 1)) <= 1.2 { col = f[3] }
                c.set(mx + xx, my + yy, col)
            }
        }
    }

    public static func gong(_ c: inout PixelCanvas, cx: Int, cy: Int, r: Int, shake: Double, flash: Bool) {
        let w = RetroPalette.standWood, wd = RetroPalette.standWoodDark, wl = RetroPalette.standWoodLight
        for side in [-1, 1] {
            let x = cx + side * (r + 6)
            for y in (cy - r - 10)...(cy + r + 16) {
                c.set(x - 1, y, wd); c.set(x, y, w); c.set(x + 1, y, wl); c.set(x + 2, y, wd)
            }
        }
        for x in (cx - r - 12)...(cx + r + 12) {
            let lift = abs(x - cx) > r + 8 ? -1 : 0
            c.set(x, cy - r - 12 + lift, wl); c.set(x, cy - r - 11 + lift, w)
            c.set(x, cy - r - 10, w); c.set(x, cy - r - 9, wd)
        }
        let sx = Int(shake.rounded()), fcx = Double(cx), fcy = Double(cy), fr = Double(r)
        c.line(fcx - 6 + Double(sx), fcy - fr - 8, fcx - 4 + Double(sx), fcy - fr + 1, RetroPalette.rope)
        c.line(fcx + 6 + Double(sx), fcy - fr - 8, fcx + 4 + Double(sx), fcy - fr + 1, RetroPalette.rope)
        let b = RetroPalette.brass
        for y in (-r - 1)...(r + 1) {
            for x in (-r - 1)...(r + 1) {
                let d = hypot(Double(x), Double(y))
                if d > fr + 0.8 { continue }
                var col: RGBA
                if d > fr - 0.2 { col = b[0] }
                else if d > fr - 2 { col = b[1] }                                   // rim
                else if d > fr - 3.2 { col = b[(x + y) < 0 ? 4 : 2] }              // raised lip catches light
                else if d < 3.5 { col = b[d < 2 ? 5 : 4] }                         // boss
                else if d < 5 { col = b[2] }
                else {                                                              // hammered gradient
                    let l = Double(-x - y) / (fr * 1.4)
                    let lv = 2 + l * 1.6 + ((x * 7 + y * 13) % 5 == 0 ? -0.6 : 0)
                    col = b[min(4, max(1, Int(lv.rounded())))]
                }
                if Double(x) < -fr * 0.3 && Double(y) < -fr * 0.3 && abs(d - fr * 0.62) < 0.8 { col = b[5] } // specular arc
                if flash && d < fr - 2 { col = d < fr * 0.7 ? .white : b[5] }
                c.set(cx + x + sx, cy + y, col)
            }
        }
    }

    /// Falling blossom. `tileWidth` repeats the scene's pattern across a wider world (offset every `tileWidth + 10`),
    /// so the scene part of the game world shows exactly the scene's petals.
    static func petals(_ c: inout PixelCanvas, time t: Double, tileWidth: Int? = nil) {
        let w = Double(tileWidth ?? c.width), h = Double(c.height)
        for tile in stride(from: 0.0, to: Double(c.width), by: w + 10) {
            petalTile(&c, time: t, width: w, height: h, offset: tile)
        }
    }

    private static func petalTile(_ c: inout PixelCanvas, time t: Double, width w: Double, height h: Double, offset: Double) {
        for i in 0..<7 {
            let di = Double(i)
            let x = offset + (di * 41 + t * 8 * (1 + Double(i % 3) * 0.5)).truncatingRemainder(dividingBy: w + 10) - 5
            let y = (di * 17 + t * 11 + sin(t + di) * 3).truncatingRemainder(dividingBy: h - 8)
            c.set(x, y, RetroPalette.petal); c.set(x + 1, y, RetroPalette.petalDark)
        }
    }

    /// Width of the game world; the modal scene is its left `SceneLayout.modal.width` columns.
    public static let worldWidth = 228

    /// The whole game world: the scene's backdrop pixel for pixel on the left, more of the landscape
    /// (a larger pagoda, a torii gate, more stars) to the right.
    public static func worldBackground(height h: Int = SceneLayout.modal.height) -> PixelCanvas {
        background(width: worldWidth, height: h, featureWidth: SceneLayout.modal.width, extras: true)
    }

    /// Dithered sunset sky, stars, moon, hills with a pagoda, wooden floor.
    /// `featureWidth` places moon, stars and pagoda as for a canvas of that width (so a wider world keeps the scene's
    /// left part identical); `extras` adds the landscape beyond it.
    static func background(width w: Int, height h: Int, featureWidth fw: Int? = nil, extras: Bool = false) -> PixelCanvas {
        let fw = fw ?? w
        var c = PixelCanvas(width: w, height: h)
        let sky = RetroPalette.sky, fh = h - 6
        let bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        for y in 0..<fh {
            let pp = Double(y) / Double(fh) * Double(sky.count - 1)
            let i = Int(pp.rounded(.down)), fr = pp - Double(i)
            for x in 0..<w {
                let step = fr * 16 > Double(bayer[y % 4][x % 4]) ? 1 : 0
                c.set(x, y, sky[min(sky.count - 1, i + step)])
            }
        }
        let starRows = max(1, Int((Double(fh) * 0.45).rounded()))
        for i in 0..<18 { c.set((i * 53) % fw, (i * 29) % starRows, i % 3 != 0 ? RetroPalette.starDim : .white) }
        if extras {
            for i in 0..<22 { c.set(fw + (i * 37) % (w - fw), (i * 23 + 5) % starRows, i % 3 != 0 ? RetroPalette.starDim : .white) }
        }

        let mx = Int((Double(fw) * 0.2).rounded()), my = Int((Double(h) * 0.34).rounded())
        let mr = Int((Double(min(fw, h)) * 0.15).rounded()), fmr = Double(mr)
        for y in (-mr - 3)...(mr + 3) {
            for x in (-mr - 3)...(mr + 3) {
                let dx = Double(x), dy = Double(y), d = hypot(dx, dy)
                if d <= fmr {
                    var col = RetroPalette.moon
                    if d > fmr - 1.5 && x + y > 0 { col = RetroPalette.moonShade }
                    if hypot(dx - fmr * 0.3, dy + fmr * 0.2) < fmr * 0.18 || hypot(dx + fmr * 0.35, dy - fmr * 0.35) < fmr * 0.12
                        || hypot(dx - fmr * 0.1, dy - fmr * 0.5) < fmr * 0.09 { col = RetroPalette.moonShade }
                    c.set(mx + x, my + y, col)
                } else if d <= fmr + 3 && (x + y) % 2 == 0 {
                    c.set(mx + x, my + y, RetroPalette.moon, alpha: 0.25)
                }
            }
        }
        func hill(amp: Double, base: Double, freq: Double, phase: Double, _ col: RGBA) {
            for x in 0..<w {
                let fx = Double(x)
                let hh = Int((base + amp * sin(fx * freq + phase) + amp * 0.5 * sin(fx * freq * 2.7 + phase * 2)).rounded())
                if hh > 0 { for y in (fh - hh)..<fh { c.set(x, y, col) } }
            }
        }
        hill(amp: 4, base: 12, freq: 0.045, phase: 1, RetroPalette.hillFar)
        func pagoda(at px0: Int, scale k: Double) {
            let py0 = fh - Int((14 * k).rounded())
            for (tw0, dy0) in [(9, 0), (7, -4), (5, -8)] {
                let tw = Int((Double(tw0) * k).rounded()), dy = Int((Double(dy0) * k).rounded())
                for x in -tw...tw { c.set(px0 + x, py0 + dy, RetroPalette.hillNear) }
                for x in (-tw + 3)...(tw - 3) { for row in 1...3 { c.set(px0 + x, py0 + dy + row, RetroPalette.hillNear) } }
            }
            let spire = Int((9 * k).rounded())
            c.set(px0, py0 - spire, RetroPalette.hillNear); c.set(px0, py0 - spire - 1, RetroPalette.hillNear)
            if k > 1 {
                // the larger pagoda stands taller than the hills behind it: give it a base down to the ground
                let base = Int((6 * k).rounded())
                for y in (py0 + 4)..<fh { for x in -base...base { c.set(px0 + x, y, RetroPalette.hillNear) } }
            }
        }
        pagoda(at: Int((Double(fw) * 0.5).rounded()), scale: 1)
        if extras {
            pagoda(at: fw + 68, scale: 1.4)
            // torii gate
            let gx = fw + 96, top = fh - 27
            for x in [gx, gx + 18] { for y in top..<fh { c.set(x, y, RetroPalette.headband[1]); c.set(x + 1, y, RetroPalette.headband[1]) } }
            for x in (gx - 4)...(gx + 23) { c.set(x, top, RetroPalette.headband[2]); c.set(x, top + 1, RetroPalette.headband[1]) }
            for x in (gx - 1)...(gx + 20) { c.set(x, top + 6, RetroPalette.headband[1]) }
        }
        hill(amp: 3, base: 6, freq: 0.08, phase: 3, RetroPalette.hillNear)
        for x in 0..<w {
            c.set(x, h - 6, RetroPalette.floorTop); c.set(x, h - 5, RetroPalette.floorEdge)
            for y in (h - 4)..<h { c.set(x, y, y == h - 1 ? RetroPalette.floorBottom : RetroPalette.floorPlank) }
            if x % 14 == 0 { for y in (h - 4)..<h { c.set(x, y, RetroPalette.floorSeam) } }
            if x % 14 == 7 { c.set(x, h - 2, RetroPalette.floorKnot) }
        }
        return c
    }

    // MARK: - Mini gong

    /// The gong on its stand on a transparent 52×56 canvas, for the secondary-screen panel.
    public static func miniGong() -> PixelCanvas {
        var c = PixelCanvas(width: 52, height: 56)
        gong(&c, cx: 26, cy: 26, r: 12, shake: 0, flash: false)
        return c
    }

    // MARK: - App icon

    /// 64×64 app icon: the gong at sunset inside a macOS-style rounded square with hard (pixel) edges.
    public static func appIcon() -> PixelCanvas {
        let size = 64, inset = 4.0, radius = 14.0
        var scene = background(width: size, height: size)
        gong(&scene, cx: 36, cy: 32, r: 16, shake: 0, flash: false)
        var out = PixelCanvas(width: size, height: size)
        let lo = inset + radius, hi = Double(size) - inset - radius
        for y in 0..<size {
            for x in 0..<size {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                guard px >= inset, py >= inset, px <= Double(size) - inset, py <= Double(size) - inset else { continue }
                let dx = max(lo - px, 0, px - hi), dy = max(lo - py, 0, py - hi)
                if dx * dx + dy * dy <= radius * radius { out.set(x, y, scene[x, y]) }
            }
        }
        return out
    }
}
