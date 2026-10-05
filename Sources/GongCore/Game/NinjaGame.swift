import Foundation

public struct GameInput: Equatable, Sendable {
    public var left: Bool
    public var right: Bool
    /// Pressed since the previous `step` (edge, not held).
    public var jump: Bool
    public var strike: Bool
    /// ↓ held: crouch when standing still.
    public var down: Bool
    /// ↓ pressed since the previous `step`: slide when walking.
    public var downPressed: Bool

    public init(left: Bool = false, right: Bool = false, jump: Bool = false, strike: Bool = false,
                down: Bool = false, downPressed: Bool = false) {
        self.left = left; self.right = right; self.jump = jump; self.strike = strike
        self.down = down; self.downPressed = downPressed
    }
}

public enum Facing: Equatable, Sendable { case left, right }
public enum ShurikenLane: Equatable, Sendable { case low, high }
public enum GameEvent: Equatable, Sendable { case deflect, hit, gameOver }
public enum GamePhase: Equatable, Sendable { case playing, gameOver }

/// "+50" floating up where a shuriken was knocked away.
public struct ScorePop: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var age: Double
}

public struct Shuriken: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public let lane: ShurikenLane
    public var deflected: Bool

    public init(x: Double, y: Double, vx: Double, vy: Double = 0, lane: ShurikenLane, deflected: Bool = false) {
        self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.lane = lane; self.deflected = deflected
    }
}

/// The shuriken game. Positions in world pixels (the scene is the world's left part); (x, y) is the top-left of the
/// ninja's 20×32 box, so its feet are at (x + 10, y + 32).
public struct NinjaGame: Equatable {
    public static let width = 228
    public static let height = SceneLayout.modal.height
    public static let spriteWidth = 20
    public static let spriteHeight = 32
    public static let floorY = Double(height - 6 - spriteHeight)
    /// Shuriken centre heights: feet and chest of a standing ninja.
    public static let lowY = Double(height - 6) - 5
    public static let highY = floorY + 8
    public static let maxLives = 3
    /// Half the size of the 7×7 shuriken sprite (hit tests use this).
    public static let shurikenRadius = 3.0
    public static let pointsPerSecond = 10.0
    public static let deflectPoints = 50
    static let popDuration = 0.7

    static let tick = 1.0 / 60
    static let maxDt = 0.1
    static let walkSpeed = 60.0
    static let jumpSpeed = 2 * 22 / 0.3       // peak 22 px after 0.3 s
    static let gravity = jumpSpeed / 0.3
    static let strikeDuration = 0.25
    static let strikeCooldown = 0.4
    static let reach = 14.0
    static let invulnerableDuration = 1.2
    static let knockback = 6.0
    static let firstSpawn = 1.0
    static let slideDuration = 0.45
    static let slideSpeed = 135.0
    /// Fraction of slide speed left after one second.
    static let slideDecay = 0.12
    static let deathHop = 90.0

    public private(set) var x: Double
    public private(set) var y: Double
    public private(set) var facing: Facing = .right
    public private(set) var lives = maxLives
    public private(set) var shurikens: [Shuriken] = []
    public private(set) var runTime = 0.0
    public private(set) var phase: GamePhase = .playing
    /// Events from the most recent `step` (sound cues for the app).
    public private(set) var events: [GameEvent] = []
    public private(set) var strikeTimer = 0.0
    public private(set) var invulnerable = 0.0
    /// Vertical speed (px/s, negative = rising) — the renderer picks jump / salto frames from it.
    public private(set) var vy = 0.0
    /// −1, 0 or 1: the direction walked in the last tick.
    public private(set) var walkDirection = 0
    public private(set) var isCrouching = false
    public private(set) var slideTimer = 0.0
    public private(set) var sinceLanding = 9.0
    /// Seconds since game over (the ninja keeps falling and tumbling).
    public private(set) var deathTime = 0.0
    public private(set) var deflects = 0
    public private(set) var pops: [ScorePop] = []

    /// 10 points per second survived, 50 per shuriken knocked away.
    public var score: Int { Int((runTime * Self.pointsPerSecond + 1e-6).rounded(.down)) + deflects * Self.deflectPoints }

    /// When false the random spawn wave is skipped (hand-placed shurikens in tests, running home in the app).
    public var autoSpawn = true

    private var slideVelocity = 0.0
    private var pendingSlide = false
    private var cooldown = 0.0
    private var spawnTimer = firstSpawn
    private var accumulator = 0.0
    private var pendingJump = false
    private var pendingStrike = false
    private var rng: SplitMix64

    public init(seed: UInt64, x startX: Double? = nil) {
        x = startX ?? Double(Self.width - Self.spriteWidth) / 2
        y = Self.floorY
        rng = SplitMix64(seed: seed)
    }

    public var isAirborne: Bool { y < Self.floorY - 0.001 }
    public var isStriking: Bool { strikeTimer > 0 }
    public var isSliding: Bool { slideTimer > 0 }

    public mutating func step(dt: Double, input: GameInput, minutesToStart: Double) {
        events = []
        accumulator += dt.isFinite ? min(max(dt, 0), Self.maxDt) : 0   // NaN would stop the clock for good
        guard phase == .playing else {
            // after game over the ninja falls to the floor and lies there; shurikens in the air fly on, none spawn
            while accumulator >= Self.tick - 1e-9 {
                accumulator -= Self.tick
                fall(Self.tick); moveFlyers(Self.tick); deathTime += Self.tick
            }
            return
        }
        pendingJump = pendingJump || input.jump
        pendingStrike = pendingStrike || input.strike
        pendingSlide = pendingSlide || input.downPressed
        while accumulator >= Self.tick - 1e-9, phase == .playing {
            accumulator -= Self.tick
            tickOnce(left: input.left, right: input.right, down: input.down, minutesToStart: minutesToStart)
        }
    }

    private mutating func fall(_ dt: Double) {
        let wasAirborne = isAirborne
        vy += Self.gravity * dt
        y += vy * dt
        if y >= Self.floorY { y = Self.floorY; vy = 0; if wasAirborne { sinceLanding = 0 } }
        sinceLanding += dt
    }

    public mutating func spawn(_ s: Shuriken) { shurikens.append(s) }


    private mutating func tickOnce(left: Bool, right: Bool, down: Bool, minutesToStart: Double) {
        let dt = Self.tick
        runTime += dt
        let maxX = Double(Self.width - Self.spriteWidth)

        let dir = (right ? 1.0 : 0) - (left ? 1.0 : 0)
        if dir != 0 { facing = dir < 0 ? .left : .right }
        if pendingSlide && !isAirborne && !isSliding && dir != 0 {
            slideTimer = Self.slideDuration
            slideVelocity = dir * Self.slideSpeed
            strikeTimer = 0
        }
        pendingSlide = false
        if isSliding {
            x = min(max(x + slideVelocity * dt, 0), maxX)
            slideVelocity *= pow(Self.slideDecay, dt)
            slideTimer = max(0, slideTimer - dt)
            walkDirection = 0
        }
        isCrouching = down && !isAirborne && !isSliding
        if !isSliding && !isCrouching {
            x = min(max(x + dir * Self.walkSpeed * dt, 0), maxX)
            walkDirection = Int(dir)
        } else if isCrouching {
            walkDirection = 0
        }

        if pendingJump && !isAirborne && !isSliding { vy = -Self.jumpSpeed; isCrouching = false }
        pendingJump = false
        fall(dt)

        if strikeTimer > 0 {
            strikeTimer -= dt
            if strikeTimer <= 0 { strikeTimer = 0; cooldown = Self.strikeCooldown }
        } else if cooldown > 0 {
            cooldown -= dt
        }
        if pendingStrike && strikeTimer <= 0 && cooldown <= 0 && !isSliding { strikeTimer = Self.strikeDuration }
        pendingStrike = false
        if invulnerable > 0 { invulnerable = max(0, invulnerable - dt) }

        if autoSpawn {
            let params = GameDifficulty.params(minutesToStart: minutesToStart, runTime: runTime)
            spawnTimer -= dt
            if spawnTimer <= 0 {
                spawnWave(params)
                spawnTimer += params.interval
            }
        }

        moveFlyers(dt)

        var hitIndex: Int?
        for i in shurikens.indices where !shurikens[i].deflected {
            let s = shurikens[i]
            if isStriking && inStrikeZone(s) {
                shurikens[i].deflected = true
                shurikens[i].vx = -s.vx * 1.2
                shurikens[i].vy = -80
                deflects += 1
                pops.append(ScorePop(x: s.x, y: s.y, age: 0))
                events.append(.deflect)
            } else if invulnerable <= 0 && hitbox(contains: s) && hitIndex == nil {
                hitIndex = i
            }
        }
        if let i = hitIndex { takeHit(from: shurikens.remove(at: i)) }
    }

    /// Score pops rise and fade; shurikens fly on and are dropped once off the screen.
    private mutating func moveFlyers(_ dt: Double) {
        for i in pops.indices { pops[i].age += dt; pops[i].y -= 18 * dt }
        pops.removeAll { $0.age >= Self.popDuration }
        for i in shurikens.indices {
            shurikens[i].x += shurikens[i].vx * dt
            shurikens[i].y += shurikens[i].vy * dt
        }
        let w = Double(Self.width)
        shurikens.removeAll { $0.x < -12 || $0.x > w + 12 || $0.y < -12 }
    }

    private mutating func spawnWave(_ p: SpawnParams) {
        if p.wall {
            for fromLeft in [true, false] { for lane in [ShurikenLane.low, .high] { add(fromLeft: fromLeft, lane: lane, speed: p.speed) } }
        } else {
            let fromLeft = rng.nextUnit() < 0.5
            let lane: ShurikenLane = rng.nextUnit() < p.highChance ? .high : .low
            add(fromLeft: fromLeft, lane: lane, speed: p.speed)
        }
    }

    private mutating func add(fromLeft: Bool, lane: ShurikenLane, speed: Double) {
        shurikens.append(Shuriken(x: fromLeft ? -6 : Double(Self.width) + 6,
                                  y: lane == .low ? Self.lowY : Self.highY,
                                  vx: fromLeft ? speed : -speed, lane: lane))
    }

    /// Body box: 10 px wide, rows 4…30 of the 32-high box; crouching or sliding only rows 17…30.
    private func hitbox(contains s: Shuriken) -> Bool {
        let low = isCrouching || isSliding
        let x0 = x + 5, x1 = x + 15, y0 = y + (low ? 17 : 4), y1 = y + 30
        let r = Self.shurikenRadius
        return s.x + r >= x0 && s.x - r <= x1 && s.y + r >= y0 && s.y - r <= y1
    }

    /// In front of the ninja (facing side), within reach, over the full sprite height, and flying toward him.
    private func inStrikeZone(_ s: Shuriken) -> Bool {
        let cx = x + Double(Self.spriteWidth) / 2
        let front = Double(Self.spriteWidth) / 2 + Self.reach
        let inX = facing == .right ? (s.x >= cx && s.x <= cx + front) : (s.x <= cx && s.x >= cx - front)
        let toward = facing == .right ? s.vx < 0 : s.vx > 0
        return inX && toward && s.y >= y && s.y <= y + Double(Self.spriteHeight)
    }

    private mutating func takeHit(from s: Shuriken) {
        lives -= 1
        events.append(.hit)
        x = min(max(x + (s.vx > 0 ? 1 : -1) * Self.knockback, 0), Double(Self.width - Self.spriteWidth))
        invulnerable = Self.invulnerableDuration
        if lives <= 0 {
            lives = 0
            phase = .gameOver
            events.append(.gameOver)
            slideTimer = 0; strikeTimer = 0; isCrouching = false
            if !isAirborne { vy = -Self.deathHop }   // knocked up, then falls
        }
    }
}
