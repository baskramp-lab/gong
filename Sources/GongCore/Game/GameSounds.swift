import Foundation

/// Tiny game cues, synthesized like the gong: a metallic *tink* (deflect) and a dull *tok* (hit).
public enum GameSounds {
    public static func tink(sampleRate sr: Int = GongSynth.sampleRate) -> [Float] {
        let n = Int(0.16 * Double(sr))
        let out = (0..<n).map { s -> Double in
            let t = Double(s) / Double(sr)
            return (sin(2 * .pi * 2_350 * t) + 0.6 * sin(2 * .pi * 3_710 * t)) * exp(-t * 32)
        }
        return normalised(out)
    }

    public static func tok(sampleRate sr: Int = GongSynth.sampleRate) -> [Float] {
        let n = Int(0.12 * Double(sr))
        var rng = SplitMix64(seed: 0x70_6B)
        var lp = 0.0
        let out = (0..<n).map { s -> Double in
            let t = Double(s) / Double(sr)
            lp += 0.15 * ((rng.nextUnit() * 2 - 1) - lp)
            return (sin(2 * .pi * (180 - 90 * t / 0.12) * t) + lp * 2) * exp(-t * 40)
        }
        return normalised(out)
    }

    private static func normalised(_ x: [Double]) -> [Float] {
        let peak = x.reduce(0) { max($0, abs($1)) }
        let g = peak > 0 ? 0.9 / peak : 0
        return x.map { Float($0 * g) }
    }
}
