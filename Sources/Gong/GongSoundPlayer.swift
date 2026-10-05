import AVFoundation
import GongCore

/// Plays the synthesized gong on every strike of a `StrikeClock` (the moment the ninja hits) over a looping
/// soundtrack, until stopped. While playing, the system output is unmuted / raised so the gong is always heard.
final class GongSoundPlayer {
    var enabled: Bool
    private let wav: Data
    private let musicWav: Data
    private let tinkWav = GongSynth.wavData(GameSounds.tink())
    private let tokWav = GongSynth.wavData(GameSounds.tok())
    private var music: AVAudioPlayer?
    private let volume = SystemVolume()
    private var timer: Timer?
    private var clock: StrikeClock?
    /// One player per strike so the 7 s tail of the previous one is not cut off.
    private var players: [AVAudioPlayer] = []

    init(enabled: Bool) {
        self.enabled = enabled
        wav = GongSynth.wavData(GongSynth.render())
        musicWav = GongSynth.wavData(SoundtrackSynth.render())
    }

    func start(clock: StrikeClock) {
        stop()
        self.clock = clock
        if enabled {
            volume.ensureAudible()
            startMusic()
        }
        schedule(after: clock.start.addingTimeInterval(-0.001))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        clock = nil
        players.forEach { $0.stop() }
        players = []
        music?.stop()
        music = nil
        volume.restore()
    }

    private func startMusic() {
        guard let player = try? AVAudioPlayer(data: musicWav) else { return }
        player.numberOfLoops = -1
        player.volume = SoundtrackSynth.mixLevel
        player.play()
        music = player
    }

    /// Absolute fire dates from the clock, so sound and animation never drift apart. Strikes missed while the Mac
    /// slept (or the main thread stalled) are skipped, not played back to back.
    private func schedule(after date: Date) {
        guard let clock else { return }
        let fire = clock.nextStrike(after: max(date, Date()))
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.play(self.wav)
            self.schedule(after: fire)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Game mode: no periodic gong (the soundtrack keeps playing).
    func pauseStrikes() {
        timer?.invalidate()
        timer = nil
    }

    func playGong() { play(wav) }
    func playTink() { play(tinkWav) }
    func playTok() { play(tokWav) }

    private func play(_ data: Data) {
        guard enabled, let player = try? AVAudioPlayer(data: data) else { return }
        players.removeAll { !$0.isPlaying }
        player.play()
        players.append(player)
    }
}
