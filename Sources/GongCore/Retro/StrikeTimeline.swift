import Foundation

/// Geometry of the scene in logical pixels.
public struct SceneLayout: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) { self.width = width; self.height = height }

    public static let modal = SceneLayout(width: 100, height: 92)

    public var gongRadius: Int { min(20, height / 2 - 14) }
    public var gongX: Int { width - gongRadius - 10 }
    public var gongY: Int { height - 6 - gongRadius - 16 }
    public var floorY: Int { height - 6 - 32 }
    public var homeX: Double { Double(max(2, gongX - gongRadius - 62)) }
    public var strikeX: Double { Double(gongX - gongRadius - 30) }
    public var airY: Double { Double(gongY - 14) }
    /// Horizontal distance the staff covers from the hand to the gong face at impact.
    public var reach: Double { Double(gongX) - Double(gongRadius) * 0.45 - (strikeX + 12 + 5) }
}

public struct ScenePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
}

public enum StaffMode: Equatable, Sendable {
    case none
    /// Two hands on the staff, angled up toward the gong.
    case guardStance(angle: Double)
    /// One-handed: angle from the shoulder (0 = toward the gong) and shaft length.
    case swing(angle: Double, length: Double)
}

/// Everything the renderer needs for one frame.
public struct SceneState: Equatable, Sendable {
    public var pose: NinjaPose = .idle
    public var x: Double
    public var y: Double
    public var rotation = 0
    public var sink = false
    public var blink = false
    public var staff: StaffMode = .none
    public var ghosts: [ScenePoint] = []
    public var speedLines = false
    public var smear = false
    public var gongShake = 0.0
    public var gongFlash = false
    public var cameraShake = 0
    /// Seconds since the hit while shock rings are visible.
    public var ringsTime: Double?
    /// Seconds since the hit while "GONG!" is visible.
    public var textTime: Double?
    /// Global seconds since the modal opened (flutter, petals, sway).
    public var time: Double
    /// 0…1 through the take-off, while the leap is drawn with the game's articulated ninja (nil otherwise).
    public var rigJump: Double?

    public var isMoving: Bool { pose == .leap || pose == .tuck }
}

/// The ninja choreography per 4 s cycle: crouch → leap → horizontal strike (hit-stop) → salto → guard.
public enum StrikeTimeline {
    public static let hitStop = 0.1

    public static func state(cycleTime: Double, time: Double, reduceMotion: Bool, layout: SceneLayout = .modal) -> SceneState {
        let hit = StrikeClock.hit
        let cyc = reduceMotion ? 5 : cycleTime
        let frozen = cyc > hit && cyc < hit + hitStop
        let tt = frozen ? hit : (cyc >= hit + hitStop ? cyc - hitStop : cyc)
        let since = reduceMotion ? -9 : cyc - hit

        let homeX = layout.homeX, strikeX = layout.strikeX, airY = layout.airY
        let floorY = Double(layout.floorY)
        var st = SceneState(x: homeX, y: floorY, time: time)

        st.gongShake = since > 0.1 ? sin(since * 40) * 3 * exp(-since * 2) : 0
        st.cameraShake = (since > 0 && since < 0.3) ? (Int((since * 40).rounded(.down)) % 2 == 1 ? 1 : -1) : 0
        st.gongFlash = frozen && !reduceMotion
        if since > 0.08 && since < 1.6 { st.ringsTime = since }
        if since > 0.08 && since < 1.1 { st.textTime = since }

        let bob = Int((time * 1.25).rounded(.down)) % 2
        st.blink = time.truncatingRemainder(dividingBy: 3.1) < 0.12
        var guardStance = false

        if tt < 0.4 {
            st.pose = .crouch; st.y = floorY + 4
            st.staff = .swing(angle: -2.4, length: 16)
        } else if tt < hit {
            let u = ease((tt - 0.4) / (hit - 0.4))
            st.pose = .leap
            st.x = lerp(homeX, strikeX, u)
            st.y = lerp(floorY, airY, sin(u * .pi / 2))
            if tt < 0.7 {
                // take-off: the game's jump pose; the staff only comes around for the strike from 0.7 s
                st.rigJump = (tt - 0.4) / 0.3
                st.staff = .swing(angle: .pi, length: lerp(20, 10, (tt - 0.55) / 0.15).rounded())
            } else {
                st.staff = .swing(angle: 0, length: lerp(3, layout.reach, (tt - 0.7) / (hit - 0.7)).rounded())
            }
            st.ghosts = (1...3).map { k in
                let uk = ease((tt - 0.4 - Double(k) * 0.035) / (hit - 0.4))
                return ScenePoint(x: lerp(homeX, strikeX, uk), y: lerp(floorY, airY, sin(uk * .pi / 2)))
            }
        } else if tt < hit + 0.12 {
            st.pose = .leap; st.x = strikeX; st.y = airY
            st.staff = .swing(angle: 0, length: layout.reach.rounded())
        } else if tt < 1.5 {
            let u = (tt - hit - 0.12) / (1.5 - hit - 0.12)
            st.pose = .tuck
            st.x = lerp(strikeX, homeX, ease(u))
            st.y = lerp(airY, floorY + 6, u * u) - sin(u * .pi) * 14
            st.rotation = (4 - Int((u * 8).rounded(.down)) % 4) % 4
        } else if tt < 1.65 {
            st.pose = .crouch; st.y = floorY + 4
            guardStance = true
        } else {
            st.pose = .idle
            guardStance = true
        }

        if guardStance {
            st.staff = .guardStance(angle: -0.62 + sin(time * 1.7) * 0.06)
            st.sink = st.pose == .idle && bob == 1
        }
        if st.pose != .idle { st.blink = false }
        st.speedLines = st.pose == .leap && !frozen && tt < hit
        st.smear = !reduceMotion && tt > 0.7 && tt < hit + 0.06
        return st
    }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * min(max(u, 0), 1) }
    static func ease(_ u: Double) -> Double { u < 0 ? 0 : u > 1 ? 1 : 1 - pow(1 - u, 3) }
}
