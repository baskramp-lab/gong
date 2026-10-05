import Foundation

/// The game's articulated ninja: a 14×11 head sprite on a 9 px torso with jointed limbs and a staff.
/// Values follow `docs/superpowers/prototypes/2026-10-02-ninja-rig.html`. Angles are measured from straight down,
/// positive = toward the facing direction; staff angles from horizontal-forward, negative = up.
public struct RigPose: Equatable, Sendable {
    public struct Limb: Equatable, Sendable {
        public var upper: Double
        public var lower: Double
        public init(_ upper: Double, _ lower: Double) { self.upper = upper; self.lower = lower }
    }

    public enum Staff: Equatable, Sendable {
        case none
        /// Held in front in the leading hand.
        case guarding(Double)
        /// Slung behind the shoulder while running or tumbling.
        case carry(Double)
        /// Swung by the leading hand (strike).
        case swing(Double)
    }

    public var lean: Double
    public var frontLeg: Limb
    public var backLeg: Limb
    public var frontArm: Limb
    public var backArm: Limb
    public var staff: Staff
    /// Grounded poses put their lowest body point on the floor; airborne ones hang from the feet point.
    public var grounded: Bool
    public var lift: Double
    /// Moves the head toward the facing side (px). Lying on his back the big head would otherwise stick out
    /// behind the torso and he would rest on the back of his head only.
    public var headShift: Double

    public init(lean: Double, frontLeg: Limb, backLeg: Limb, frontArm: Limb, backArm: Limb, staff: Staff,
                grounded: Bool, lift: Double = 0, headShift: Double = 0) {
        self.lean = lean; self.frontLeg = frontLeg; self.backLeg = backLeg
        self.frontArm = frontArm; self.backArm = backArm; self.staff = staff
        self.grounded = grounded; self.lift = lift; self.headShift = headShift
    }

    public var staffAngle: Double? {
        switch staff {
        case .none: return nil
        case .guarding(let a), .carry(let a), .swing(let a): return a
        }
    }
}

/// The animation library: every pose the game needs, as functions of time or progress.
public enum RigPoses {
    typealias L = RigPose.Limb

    public static func idle(_ t: Double) -> RigPose {
        let b = sin(t * 2.6)
        return RigPose(lean: 0.1 + b * 0.02, frontLeg: L(0.62, 0.05), backLeg: L(-0.6, -0.15),
                       frontArm: L(0.7, 2.05 + b * 0.05), backArm: L(0.35, 1.75),
                       staff: .guarding(-0.65 + sin(t * 1.7) * 0.05), grounded: true)
    }

    /// Run cycle; `t` in seconds at walking speed (2.3 strides per second).
    public static func run(_ t: Double) -> RigPose {
        let p = t * .pi * 2 * 2.3
        func leg(_ ph: Double) -> L { let th = 0.8 * sin(ph); return L(th, th - (0.25 + 1.1 * max(0, cos(ph)))) }
        return RigPose(lean: 0.32, frontLeg: leg(p), backLeg: leg(p + .pi),
                       frontArm: L(-0.5 * sin(p) + 0.3, 0.9), backArm: L(0.6 * sin(p) - 0.2, 0.6),
                       staff: .carry(-0.25), grounded: true)
    }

    /// Take-off, apex and fall poses by vertical speed (px/s, negative = rising).
    public static func jump(vy: Double) -> RigPose {
        if vy < -60 {
            return RigPose(lean: 0.05, frontLeg: L(0.35, 0.1), backLeg: L(-0.25, -0.55),
                           frontArm: L(2.7, 2.95), backArm: L(2.4, 2.7), staff: .guarding(-1.35), grounded: false)
        }
        if vy < 50 {
            return RigPose(lean: 0.25, frontLeg: L(1.55, -0.25), backLeg: L(1.15, -0.6),
                           frontArm: L(1.45, 2.0), backArm: L(1.0, 1.6), staff: .guarding(-0.3), grounded: false, lift: 3)
        }
        return RigPose(lean: 0.05, frontLeg: L(0.5, 0.05), backLeg: L(-0.35, -0.2),
                       frontArm: L(1.9, 2.2), backArm: L(-0.9, -0.4), staff: .guarding(-0.9), grounded: false)
    }

    /// Knees to the chest: the salto and the death tumble.
    public static func tuck() -> RigPose {
        RigPose(lean: 0.2, frontLeg: L(2.0, -0.4), backLeg: L(1.75, -0.7),
                frontArm: L(1.6, 2.6), backArm: L(1.3, 2.3), staff: .carry(-0.25), grounded: false, lift: 4)
    }

    /// Landing squash, `u` 0…1 over 0.14 s.
    public static func land(_ u: Double) -> RigPose {
        let k = sin(min(max(u, 0), 1) * .pi)
        return RigPose(lean: 0.25 * k + 0.1, frontLeg: L(lerp(0.62, 1.3, k), lerp(0.05, -0.55, k)),
                       backLeg: L(lerp(-0.6, -0.2, k), lerp(-0.15, -1.25, k)),
                       frontArm: L(0.7, 2.05 - 0.4 * k), backArm: L(0.35 + 0.5 * k, 1.75),
                       staff: .guarding(-0.65 + 0.25 * k), grounded: true)
    }

    /// Deep crouch: back knee on the floor.
    public static func crouch(_ t: Double) -> RigPose {
        let b = sin(t * 2.6)
        return RigPose(lean: 0.85 + b * 0.02, frontLeg: L(1.75, -0.95), backLeg: L(-1.2, -1.6),
                       frontArm: L(1.15, 2.1), backArm: L(0.8, 1.6),
                       staff: .guarding(-0.25 + sin(t * 1.7) * 0.04), grounded: true)
    }

    /// Low slide, `u` 0…1 over the slide; rises back up in the last 20 %.
    public static func slide(_ u: Double) -> RigPose {
        let k = min(1, max(0, u) * 5), rise = max(0, (u - 0.8) / 0.2)
        return RigPose(lean: lerp(0.2, -1.35, k) * (1 - rise) + 0.3 * rise,
                       frontLeg: L(lerp(0.6, 1.5, k), lerp(0.1, 1.55, k)), backLeg: L(lerp(-0.4, 1.3, k), lerp(-0.2, -1.4, k)),
                       frontArm: L(lerp(0.7, 1.6, k), lerp(2, 1.4, k)), backArm: L(lerp(0.4, -1.1, k), lerp(1.7, -0.6, k)),
                       staff: .carry(lerp(-0.25, 0.2, k)), grounded: true)
    }

    /// Strike, `u` 0…1 over 0.25 s: wind-up behind (22 %), fast swing (33 %), follow-through.
    public static func strike(_ u: Double) -> RigPose {
        let a: Double, lean: Double, front: L
        if u < 0.22 {
            let k = ease(u / 0.22); a = lerp(-0.65, -2.55, k); lean = lerp(0.1, -0.12, k); front = L(lerp(0.62, 0.4, k), 0.05)
        } else if u < 0.55 {
            let k = easeIn((u - 0.22) / 0.33); a = lerp(-2.55, 0.45, k); lean = lerp(-0.12, 0.42, k)
            front = L(lerp(0.4, 1.05, k), lerp(0.05, 0.2, k))
        } else {
            let k = ease((u - 0.55) / 0.45); a = lerp(0.45, 0.1, k); lean = lerp(0.42, 0.25, k); front = L(1.05, 0.2)
        }
        let arm = a + .pi / 2
        return RigPose(lean: lean, frontLeg: front, backLeg: L(-0.75, -0.25),
                       frontArm: L(arm - 0.1, arm), backArm: L(arm - 0.5, arm - 0.2), staff: .swing(a), grounded: true)
    }

    /// Recoil after a hit, `u` 0…1 over 0.35 s.
    public static func hurt(_ u: Double) -> RigPose {
        let k = sin(min(1, max(0, u) * 1.3) * .pi)
        return RigPose(lean: -0.45 * k + 0.1 * (1 - k), frontLeg: L(0.3 + 0.3 * k, -0.2), backLeg: L(-0.75, -0.35),
                       frontArm: L(2.4 * k + 0.7 * (1 - k), 2.6 * k + 2 * (1 - k)), backArm: L(-1.0 * k + 0.35, -0.6 * k + 1.75),
                       staff: .guarding(-1.6 * k - 0.65 * (1 - k)), grounded: true)
    }

    /// Knocked out: stretched out, arms along the body. Drawn a quarter turn backwards (face up) so he lies on his
    /// back: the head moves forward and the legs back so back of the head, back and calves all touch the floor.
    public static func down() -> RigPose {
        RigPose(lean: 0, frontLeg: L(-0.2, -0.2), backLeg: L(-0.24, -0.26), frontArm: L(-0.05, 0.1), backArm: L(-0.2, -0.15),
                staff: .none, grounded: true, headShift: 2)
    }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * min(max(u, 0), 1) }
    static func ease(_ u: Double) -> Double { 1 - pow(1 - min(max(u, 0), 1), 3) }
    static func easeIn(_ u: Double) -> Double { pow(min(max(u, 0), 1), 2.2) }
}

public struct RigOptions: Equatable, Sendable {
    public var time: Double
    /// Movement speed (px/s) — headband tails stream behind when fast.
    public var speed: Double
    public var blink: Bool
    /// White hit flash.
    public var flash: Bool
    /// 0…1 toward ink (Reduce Motion invulnerability).
    public var darken: Double
    /// Staff after-images during a strike: (staff angle, alpha).
    public var smear: [Smear]
    public var alpha: Double
    /// Headband tails; off for a ninja lying on the floor (they would hang below his body).
    public var tails: Bool

    public struct Smear: Equatable, Sendable {
        public var angle: Double
        public var alpha: Double
        public init(angle: Double, alpha: Double) { self.angle = angle; self.alpha = alpha }
    }

    public init(time: Double = 0, speed: Double = 0, blink: Bool = false, flash: Bool = false, darken: Double = 0,
                smear: [Smear] = [], alpha: Double = 1, tails: Bool = true) {
        self.time = time; self.speed = speed; self.blink = blink; self.flash = flash
        self.darken = darken; self.smear = smear; self.alpha = alpha; self.tails = tails
    }
}

public enum NinjaRig {
    static let thigh = 6.0, shin = 6.0, upperArm = 5.0, forearm = 4.0, torso = 9.0

    static let head = [
        "....ssssss....", "..ssssssssss..", ".ssssssssssss.", "ssssssssssssss", "rrrrrrrrrrrrrr",
        "sssssskkkkkkss", "sssssKWPkkWPks", "ssssssKkkkkkss", "ssssssssssssss", ".ssssssssssss.", "...ssssssss...",
    ].map { Array($0) }

    struct P { var x: Double; var y: Double }

    /// Draws one pose with its feet point at (x, y). Returns nothing; everything goes into `c`.
    public static func draw(_ pose: RigPose, into c: inout PixelCanvas, x: Double, y: Double, facing f: Double,
                            options o: RigOptions = RigOptions()) {
        func tone(_ col: RGBA) -> RGBA {
            if o.flash { return .white }
            guard o.darken > 0 else { return col }
            let ink = RetroPalette.ink, k = o.darken
            func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * (1 - k) + Double(b) * k).rounded()) }
            return RGBA(r: m(col.r, ink.r), g: m(col.g, ink.g), b: m(col.b, ink.b), a: col.a)
        }
        func put(_ px: Double, _ py: Double, _ col: RGBA) { c.set(px, py, tone(col), alpha: o.alpha) }
        func stamp(_ a: P, _ b: P, _ col: RGBA, _ t: Int) { c.line(a.x, a.y, b.x, b.y, tone(col), thickness: t, alpha: o.alpha) }
        func dir(_ a: Double) -> P { P(x: sin(a) * f, y: cos(a)) }
        func add(_ p: P, _ d: P, _ k: Double) -> P { P(x: p.x + d.x * k, y: p.y + d.y * k) }
        func limb(_ a: P, _ b: P, back: Bool) {
            let suit = RetroPalette.suit
            stamp(a, b, suit[0], 4)
            stamp(a, b, back ? suit[1] : suit[2], 2)
            if !back { stamp(P(x: a.x - 0.6, y: a.y - 0.6), P(x: b.x - 0.6, y: b.y - 0.6), suit[3], 1) }
        }
        func leg(_ hip: P, _ l: RigPose.Limb) -> (knee: P, foot: P) {
            let k = add(hip, dir(l.upper), thigh); return (k, add(k, dir(l.lower), shin))
        }

        // Ground the lowest body point (hip, knees, feet, elbows, hands — never the staff or head) so its 4 px limb
        // ends on row y − 1, like the scene sprites that stand on the floor line.
        let up = P(x: sin(pose.lean) * f, y: -cos(pose.lean))
        func skeleton(hip: P) -> (legs: [(knee: P, foot: P)], shoulder: P, neck: P, arms: [(elbow: P, hand: P)]) {
            let shoulder = add(hip, up, torso - 1.5)
            func arm(_ l: RigPose.Limb) -> (elbow: P, hand: P) {
                let e = add(shoulder, dir(l.upper), upperArm); return (e, add(e, dir(l.lower), forearm))
            }
            return ([leg(hip, pose.frontLeg), leg(hip, pose.backLeg)], shoulder, add(hip, up, torso),
                    [arm(pose.frontArm), arm(pose.backArm)])
        }
        let probe = skeleton(hip: P(x: 0, y: 0))
        let low = max(0, (probe.legs.flatMap { [$0.knee.y, $0.foot.y] } + probe.arms.flatMap { [$0.elbow.y, $0.hand.y] }).max() ?? 0)
        let hip = P(x: x, y: pose.grounded ? y - 2.5 - low : y - 14.5 - pose.lift)
        let sk = skeleton(hip: hip)
        let neck = sk.neck, shoulder = sk.shoulder, legs = sk.legs
        let frontArm = sk.arms[0], backArm = sk.arms[1]

        // headband tails
        let tailBase = add(neck, up, 4.5)
        let fast = o.speed > 20
        for i in 1...8 where o.tails {
            let di = Double(i)
            let wave = sin(o.time * (fast ? 16 : 5) + di * 0.8) * (di / 8) * (fast ? 3 : 1.3)
            let sag = fast ? -di * 0.15 : di * 0.35
            put(tailBase.x - f * (5 + di), tailBase.y + wave + sag, RetroPalette.headband[i % 3 != 0 ? 2 : 3])
            put(tailBase.x - f * (5 + di), tailBase.y + 1 + wave + sag, RetroPalette.headband[1])
        }

        // back leg and arm
        limb(hip, legs[1].knee, back: true); limb(legs[1].knee, legs[1].foot, back: true)
        stamp(legs[1].foot, P(x: legs[1].foot.x + f * 2, y: legs[1].foot.y), RetroPalette.band[1], 2)
        limb(shoulder, backArm.elbow, back: true); limb(backArm.elbow, backArm.hand, back: true)

        func drawStaff() {
            let hand: P, from: Double, to: Double, knobAt: Double, angle: Double
            switch pose.staff {
            case .none: return
            case .carry(let a): hand = add(shoulder, P(x: -f, y: 1), 1); from = -12; to = 10; knobAt = 12; angle = a
            case .guarding(let a), .swing(let a): hand = frontArm.hand; from = -9; to = 15; knobAt = 18; angle = a
            }
            let d = P(x: cos(angle) * f, y: sin(angle))
            let a0 = add(hand, d, from), a1 = add(hand, d, to)
            stamp(P(x: a0.x + 0.6, y: a0.y + 1), P(x: a1.x + 0.6, y: a1.y + 1), RetroPalette.wood[0], 1)
            stamp(a0, a1, RetroPalette.wood[2], 1)
            let k = add(hand, d, knobAt), fe = RetroPalette.felt
            for yy in -3...3 {
                for xx in -3...3 {
                    let dd = hypot(Double(xx), Double(yy)); if dd > 3.2 { continue }
                    var col = dd > 2.4 ? fe[0] : fe[2]
                    if dd <= 2.4 && xx + yy >= 2 { col = fe[1] }
                    if dd <= 2.4 && Double((xx + 1) * (xx + 1) + (yy + 1) * (yy + 1)) <= 1.2 { col = fe[3] }
                    put(k.x + Double(xx), k.y + Double(yy), col)
                }
            }
            for s in o.smear {
                let sd = P(x: cos(s.angle) * f, y: sin(s.angle))
                for r in 8...18 {
                    let p = add(hand, sd, Double(r))
                    c.set(p.x, p.y, tone(r > 14 ? .white : RetroPalette.gold), alpha: s.alpha * o.alpha)
                }
            }
        }
        if case .carry = pose.staff { drawStaff() }

        // torso: outline spans, then fill with belt and a lit edge
        for k in stride(from: 0.0, through: torso, by: 0.5) {
            let p = add(hip, up, k), w = lerp(4.5, 3.5, k / torso)
            stamp(P(x: p.x - w - 0.5, y: p.y), P(x: p.x + w + 0.5, y: p.y), RetroPalette.suit[0], 1)
        }
        for k in stride(from: 0.5, through: torso - 0.5, by: 0.5) {
            let p = add(hip, up, k), w = lerp(3.5, 2.5, k / torso)
            let belt = k >= 1.5 && k <= 2.5
            stamp(P(x: p.x - w, y: p.y), P(x: p.x + w, y: p.y), belt ? RetroPalette.band[2] : RetroPalette.suit[2], 1)
            put(p.x - f * w, p.y, belt ? RetroPalette.band[3] : RetroPalette.suit[3])
        }

        // front leg
        limb(hip, legs[0].knee, back: false); limb(legs[0].knee, legs[0].foot, back: false)
        stamp(legs[0].foot, P(x: legs[0].foot.x + f * 2, y: legs[0].foot.y), RetroPalette.band[2], 2)

        // head
        let h = add(add(neck, up, 5), P(x: f, y: 0), pose.headShift)
        drawHead(&c, cx: Int(h.x.rounded()), cy: Int(h.y.rounded()), facing: f, blink: o.blink, tone: tone, alpha: o.alpha)

        // front arm and staff
        if case .carry = pose.staff {} else { drawStaff() }
        limb(shoulder, frontArm.elbow, back: false); limb(frontArm.elbow, frontArm.hand, back: false)
        c.fillRect(x: Int(frontArm.hand.x.rounded()) - 1, y: Int(frontArm.hand.y.rounded()) - 1, w: 2, h: 2,
                   tone(RetroPalette.skin[2]), alpha: o.alpha)
    }

    /// Draws a pose, optionally turned by quarter turns around the body (salto, tumble) and/or with its lowest
    /// opaque pixel resting on the floor row just above `y` (lying down).
    public static func render(_ pose: RigPose, into c: inout PixelCanvas, x: Double, y: Double, facing: Double,
                              options: RigOptions = RigOptions(), quarterTurns: Int = 0, ground: Bool = false) {
        guard quarterTurns % 4 != 0 || ground else {
            draw(pose, into: &c, x: x, y: y, facing: facing, options: options); return
        }
        var off = PixelCanvas(width: 60, height: 60)
        var opaque = options; opaque.alpha = 1
        if ground { opaque.tails = false }
        draw(pose, into: &off, x: 30, y: 44, facing: facing, options: opaque)
        let turned = off.rotated(quarterTurns: quarterTurns)
        var top = y - 44
        if ground, let bottom = turned.lowestOpaqueRow { top = y - 1 - Double(bottom) }
        c.draw(turned, x: Int((x - 30).rounded()), y: Int(top.rounded()), alpha: options.alpha)
    }

    static func drawHead(_ c: inout PixelCanvas, cx: Int, cy: Int, facing f: Double, blink: Bool,
                         tone: (RGBA) -> RGBA, alpha: Double) {
        let rows = head.count, cols = head[0].count
        func empty(_ x: Int, _ y: Int) -> Bool { y < 0 || y >= rows || x < 0 || x >= cols || head[y][x] == "." }
        for y in 0..<rows {
            for x in 0..<cols {
                var ch = head[y][x]
                if ch == "." { continue }
                if blink && y == 6 && (ch == "W" || ch == "P" || ch == "K") { ch = "k" }
                let col: RGBA
                switch ch {
                case "W": col = .white
                case "P", "K": col = RetroPalette.suit[0]
                default:
                    let ramp = ch == "s" ? RetroPalette.suit : ch == "r" ? RetroPalette.headband : RetroPalette.skin
                    if empty(x + 1, y) || empty(x, y + 1) { col = ramp[0] }
                    else if empty(x - 1, y) || empty(x, y - 1) { col = ramp[3] }
                    else if empty(x + 2, y + 1) || empty(x + 1, y + 2) { col = ramp[1] }
                    else { col = ramp[2] }
                }
                let gx = f > 0 ? x : cols - 1 - x
                c.set(cx - 7 + gx, cy - 6 + y, tone(col), alpha: alpha)
            }
        }
    }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * min(max(u, 0), 1) }
}
