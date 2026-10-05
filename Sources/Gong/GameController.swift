import AppKit
import GongCore

/// Easter egg: the modal scene opens up into the game world, which stays until the modal closes (one run per meeting). Owns the running `NinjaGame` and the scene's
/// `StrikeClock`, turns key events into input, steps the game per frame and plays the cues.
final class GameController: ObservableObject {
    enum Phase: Equatable {
        /// The normal modal: sprite ninja striking the gong every 4 s.
        case scene
        /// Scene → world: the picture widens to the right, the info column folds away.
        case expanding(since: Date)
        /// The ninja walks to the middle of the world by himself; then the shurikens come.
        case entering
        /// Playing, and after game over: the world stays with the meeting buttons under it.
        case playing
    }

    static let transition = 0.45
    /// Scene choreography is back in its guard stance from this point in each cycle.
    static let sceneIdleFrom = 1.7

    @Published private(set) var phase: Phase = .scene
    /// Drives the scene animation and the gong strikes.
    let sceneClock: StrikeClock
    private(set) var game = NinjaGame(seed: 0)
    private(set) var best: Int
    private(set) var newHigh = false
    private var gameOverAt: Date?
    /// One chance per meeting: false once this meeting's game has been played (or for a meeting already played).
    @Published private(set) var canPlay: Bool
    /// The score of this meeting's game, shown under the scene afterwards.
    @Published private(set) var lastScore: Int?
    private let onPlayed: () -> Void

    private let sound: GongSoundPlayer
    private let saveBest: (Int) -> Void
    private var heldLeft = false, heldRight = false, heldDown = false
    private var resignObserver: NSObjectProtocol?
    private var pendingJump = false, pendingStrike = false, pendingDown = false
    private var lastStep: Date?
    private var pendingStart: DispatchWorkItem?

    private enum Key {
        static let space: UInt16 = 49, left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    }

    init(sound: GongSoundPlayer, best: Int, clock: StrikeClock = StrikeClock(start: Date()), canPlay: Bool = true,
         saveBest: @escaping (Int) -> Void, onPlayed: @escaping () -> Void = {}) {
        self.sound = sound
        self.best = best
        self.sceneClock = clock
        self.canPlay = canPlay
        self.saveBest = saveBest
        self.onPlayed = onPlayed
        // Key-ups go to the other app after Cmd-Tab: let go of everything so the ninja doesn't keep walking.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.heldLeft = false; self?.heldRight = false; self?.heldDown = false
        }
    }

    deinit { resignObserver.map(NotificationCenter.default.removeObserver) }

    var isActive: Bool { phase != .scene }

    /// A run is under way (not the scene, not the game-over screen).
    var isMidRun: Bool {
        switch phase {
        case .scene: return false
        case .expanding, .entering: return true
        case .playing: return game.phase == .playing
        }
    }

    /// 0 = scene layout, 1 = full world.
    func progress(at date: Date) -> Double {
        func eased(_ since: Date) -> Double {
            let u = min(max(date.timeIntervalSince(since) / Self.transition, 0), 1)
            return 1 - pow(1 - u, 3)
        }
        switch phase {
        case .scene: return 0
        case .expanding(let since): return eased(since)
        case .entering, .playing: return 1
        }
    }

    /// Visible world width in logical pixels (scene 100 → world 228).
    func viewWidth(at date: Date) -> Int {
        let p = progress(at: date)
        let scene = Double(SceneLayout.modal.width), world = Double(NinjaGame.width)
        return Int((scene + (world - scene) * p).rounded())
    }

    /// Space in the scene: start now if the ninja is in guard, otherwise as soon as his gong strike is done.
    func requestStart() {
        guard phase == .scene, pendingStart == nil, canPlay else { return }
        let cycle = sceneClock.cycleTime(at: Date())
        let wait = cycle < Self.sceneIdleFrom ? Self.sceneIdleFrom - cycle : 0
        let work = DispatchWorkItem { [weak self] in self?.pendingStart = nil; self?.begin() }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func begin() {
        guard phase == .scene, canPlay else { return }
        canPlay = false
        onPlayed()
        newGame(at: Double(SceneLayout.modal.homeX))
        sound.pauseStrikes()
        phase = .expanding(since: Date())
    }

    /// Where the ninja walks to before the shurikens start.
    static var centreX: Double { Double(NinjaGame.width - NinjaGame.spriteWidth) / 2 }

    private func newGame(at x: Double) {
        game = NinjaGame(seed: UInt64.random(in: 1...UInt64.max), x: x)
        game.autoSpawn = false   // on once he is in the middle
        newHigh = false
        gameOverAt = nil
        lastStep = nil
        heldLeft = false; heldRight = false; heldDown = false
        pendingJump = false; pendingStrike = false; pendingDown = false
    }

    /// The run is over: keep the score; it counts for the record.
    private func finish(at date: Date) {
        guard lastScore == nil else { return }
        lastScore = game.score
        if game.score > best { best = game.score; newHigh = true; saveBest(best) }
    }

    /// `--snapshot --gameover`: a lost run, straight into the game-over state (no transitions, no sound).
    func snapshotGameOver() {
        canPlay = false
        newGame(at: Self.centreX)
        game.autoSpawn = true
        phase = .playing
        while game.phase != .gameOver { game.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 0) }
        for _ in 0..<120 { game.step(dt: 1.0 / 60, input: GameInput(), minutesToStart: 0) }
        gameOverAt = .distantPast
        finish(at: Date())
    }

    /// Modal closed: drop everything.
    func exit() {
        pendingStart?.cancel(); pendingStart = nil
        phase = .scene
    }

    /// Returns true when the event is consumed (so SwiftUI does not press the focused button).
    func handle(_ e: NSEvent) -> Bool {
        let down = e.type == .keyDown
        switch phase {
        case .scene:
            if down && e.keyCode == Key.space && !e.isARepeat { requestStart(); return true }
            return false
        case .expanding, .entering:
            return [Key.space, Key.left, Key.right, Key.down, Key.up].contains(e.keyCode)
        case .playing:
            break
        }
        switch e.keyCode {
        case Key.left: heldLeft = down; return true
        case Key.right: heldRight = down; return true
        case Key.down:
            if down && !e.isARepeat { pendingDown = true }
            heldDown = down
            return true
        case Key.up: if down && !e.isARepeat { pendingJump = true }; return true
        case Key.space:
            if down && !e.isARepeat && game.phase == .playing { pendingStrike = true }   // no restart: one chance
            return true
        default: return false   // Enter etc. go to the modal
        }
    }

    func step(at date: Date, minutesToStart: Double) {
        guard phase != .scene else { return }
        let dt = lastStep.map { date.timeIntervalSince($0) } ?? 0
        lastStep = date

        var input = GameInput()
        switch phase {
        case .expanding(let since):
            if date.timeIntervalSince(since) >= Self.transition { phase = .entering }
        case .entering:
            let d = Self.centreX - game.x
            if abs(d) <= 1 {
                game.autoSpawn = true
                phase = .playing
            } else {
                input = GameInput(left: d < 0, right: d > 0)
            }
        case .playing:
            input = GameInput(left: heldLeft, right: heldRight, jump: pendingJump, strike: pendingStrike,
                              down: heldDown, downPressed: pendingDown)
            pendingJump = false; pendingStrike = false; pendingDown = false
        case .scene:
            return
        }

        game.step(dt: dt, input: input, minutesToStart: minutesToStart)
        for e in game.events {
            switch e {
            case .deflect: sound.playTink()
            case .hit: sound.playTok()
            case .gameOver:
                sound.playGong()
                gameOverAt = date
                finish(at: date)
            }
        }
    }

    /// Camera shake for 0.3 s after game over (±1 px).
    func shake(at date: Date) -> Int {
        guard let t = gameOverAt.map({ date.timeIntervalSince($0) }), t < 0.3 else { return 0 }
        return Int((t * 40).rounded(.down)) % 2 == 1 ? 1 : -1
    }
}
