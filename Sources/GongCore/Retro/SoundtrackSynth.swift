import Foundation

/// Offline synthesis of a looping chiptune in the Japanese *in* scale on D (the gong's own pitch):
/// a pulse-wave "shakuhachi" lead with delayed vibrato, Karplus–Strong koto plucks, a triangle bass,
/// taiko and kakko — kept sparse so it sits under the gong. 120 BPM, 16 bars = 32 s = four strike cycles. Tails wrap around so the loop is seamless.
public enum SoundtrackSynth {
    public static let sampleRate = GongSynth.sampleRate
    public static let bpm = 120.0
    public static let bars = 16
    /// Playback level relative to the gong (which plays at full volume).
    public static let mixLevel: Float = 0.2
    /// Eighth notes per bar (4/4).
    static let stepsPerBar = 8
    public static var stepDuration: Double { 60 / bpm / 2 }
    public static var duration: Double { Double(bars * stepsPerBar) * stepDuration }

    /// *In* scale (miyako-bushi) on D: D E♭ G A B♭.
    static let scale = [0, 1, 5, 7, 8]
    static let d4 = 293.66

    /// Scale degree → Hz; degree 0 = D4, 5 = D5, −5 = D3.
    public static func frequency(degree: Int) -> Double {
        let oct = Int((Double(degree) / 5).rounded(.down))
        let idx = degree - oct * 5
        return d4 * pow(2, Double(12 * oct + scale[idx]) / 12)
    }

    // One char per eighth: digit = scale degree, "-" = hold, "." = rest.
    static let lead = [
        "5-4-3---", "2-3-4-3-", "5-6-5-4-", "3-------",
        "5-4-3---", "2-3-4-5-", "7-6-5-4-", "5-------",
        "8-7-5---", "6-5-4-5-", "3-4-2-1-", "0-------",
        "5-4-3-2-", "3-4-5-6-", "5-4-3-2-", "0---....",
    ].joined()
    /// Koto: same notation, an octave down.
    static let koto = [
        "0.3.5.3.", "0.3.5.3.", "4.2.0.2.", "3.0.3.5.",
    ].joined()
    /// Bass root per bar (scale degree, two octaves down).
    static let bass = [0, 0, 4, 3, 0, 0, 4, 3, 4, 4, 3, 0, 0, 2, 3, 0]
    /// "X" = big taiko, "x" = taiko, "k" = kakko.
    static let drums = [
        "X.......", "......k.", "x.......", "....x.k.",
    ].joined()

    public static func render(sampleRate sr: Int = sampleRate) -> [Float] {
        let fsr = Double(sr)
        let n = Int(duration * fsr)
        var mix = [Double](repeating: 0, count: n)
        let step = Int(stepDuration * fsr)
        var rng = SplitMix64(seed: 0x4E_49_4E_4A)

        for (degree, length) in notes(lead) {
            addLead(&mix, sr: fsr, at: degree.step * step, freq: frequency(degree: degree.value), length: length * step)
        }
        let kotoSteps = Array(koto)
        for s in 0..<(bars * stepsPerBar) {
            if let d = kotoSteps[s % kotoSteps.count].wholeNumberValue {
                addKoto(&mix, sr: fsr, at: s * step, freq: frequency(degree: d - 5), rng: &rng)
            }
        }
        for (bar, d) in bass.enumerated() {
            for beat in 0..<4 {
                addBass(&mix, sr: fsr, at: (bar * stepsPerBar + beat * 2) * step, freq: frequency(degree: d - 10))
            }
        }
        let drumSteps = Array(drums)
        for s in 0..<(bars * stepsPerBar) {
            switch drumSteps[s % drumSteps.count] {
            case "X": addTaiko(&mix, sr: fsr, at: s * step, level: 1.0, rng: &rng)
            case "x": addTaiko(&mix, sr: fsr, at: s * step, level: 0.6, rng: &rng)
            case "k": addKakko(&mix, sr: fsr, at: s * step, rng: &rng)
            default: break
            }
        }

        let peak = mix.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? 0.9 / peak : 0
        return mix.map { Float($0 * gain) }
    }

    struct Degree { let step: Int; let value: Int }

    /// Parses the lead line into (start step + degree, length in steps).
    static func notes(_ line: String) -> [(Degree, Int)] {
        var out: [(Degree, Int)] = []
        for (s, c) in line.enumerated() {
            if let d = c.wholeNumberValue {
                out.append((Degree(step: s, value: d), 1))
            } else if c == "-", let last = out.popLast() {
                out.append((last.0, last.1 + 1))
            }
        }
        return out
    }

    /// Adds into the loop buffer, wrapping past the end so tails continue at the start.
    private static func add(_ out: inout [Double], _ i: Int, _ v: Double) {
        out[i % out.count] += v
    }

    /// 25 % pulse, soft attack, vibrato fading in after 150 ms, one-pole low-pass to take the edge off.
    private static func addLead(_ out: inout [Double], sr: Double, at start: Int, freq: Double, length: Int) {
        let release = Int(0.08 * sr), total = length + release
        let alpha = 1 - exp(-2 * .pi * 1_400 / sr)
        var phase = 0.0, y = 0.0
        for s in 0..<total {
            let t = Double(s) / sr
            let vib = 1 + 0.006 * sin(2 * .pi * 5.5 * t) * min(1, max(0, (t - 0.15) / 0.2))
            phase += freq * vib / sr
            phase -= phase.rounded(.down)
            let x = phase < 0.25 ? 1.0 : -0.33
            y += alpha * (x - y)
            let env = min(1, t / 0.04) * (s < length ? 1 : 1 - Double(s - length) / Double(release))
            add(&out, start + s, y * env * 0.2)
        }
    }

    /// Karplus–Strong pluck: a noise burst in a delay line, averaged each pass.
    private static func addKoto(_ out: inout [Double], sr: Double, at start: Int, freq: Double, rng: inout SplitMix64) {
        let period = max(2, Int((sr / freq).rounded()))
        var line = (0..<period).map { _ in rng.nextUnit() * 2 - 1 }
        var idx = 0
        for s in 0..<Int(1.4 * sr) {
            let next = (idx + 1) % period
            let v = line[idx]
            line[idx] = 0.993 * 0.5 * (v + line[next])
            idx = next
            add(&out, start + s, v * 0.2)
        }
    }

    /// Triangle bass, short and round.
    private static func addBass(_ out: inout [Double], sr: Double, at start: Int, freq: Double) {
        var phase = 0.0
        for s in 0..<Int(0.42 * sr) {
            let t = Double(s) / sr
            phase += freq / sr
            phase -= phase.rounded(.down)
            let tri = 4 * abs(phase - 0.5) - 1
            add(&out, start + s, tri * min(1, t / 0.005) * exp(-t * 5) * 0.32)
        }
    }

    /// Sine that drops 110 → 55 Hz, plus a little low noise for the skin.
    private static func addTaiko(_ out: inout [Double], sr: Double, at start: Int, level: Double, rng: inout SplitMix64) {
        var phase = 0.0, lp = 0.0
        for s in 0..<Int(0.6 * sr) {
            let t = Double(s) / sr
            phase += (55 + 55 * exp(-t * 18)) / sr
            let noise = rng.nextUnit() * 2 - 1
            lp += 0.08 * (noise - lp)
            let body = sin(2 * .pi * phase) * exp(-t * 6)
            add(&out, start + s, (body + lp * exp(-t * 30) * 1.5) * level * 0.55)
        }
    }

    /// Dry wooden click: 1.6 kHz square with a 25 ms decay.
    private static func addKakko(_ out: inout [Double], sr: Double, at start: Int, rng: inout SplitMix64) {
        for s in 0..<Int(0.05 * sr) {
            let t = Double(s) / sr
            let sq = sin(2 * .pi * 1_600 * t) > 0 ? 1.0 : -1.0
            add(&out, start + s, (sq * 0.7 + (rng.nextUnit() * 2 - 1) * 0.3) * exp(-t * 40) * 0.12)
        }
    }
}
