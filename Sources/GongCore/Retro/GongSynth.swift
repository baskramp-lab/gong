import Foundation

/// Offline synthesis of a warm gong: eight inharmonic partials, each a slightly detuned sine pair (beating),
/// higher partials blooming in after the strike, and a low-passed mallet thump. Rendered once, played many times.
public enum GongSynth {
    public static let sampleRate = 44_100
    public static let duration = 7.0

    static let fundamental = 73.0
    static let ratios = [1, 1.52, 2.03, 2.71, 3.41, 4.23, 5.4, 6.79]
    static let amplitudes = [1, 0.75, 0.6, 0.5, 0.38, 0.3, 0.2, 0.12]
    static let blooms = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.1]

    public static func render(sampleRate sr: Int = sampleRate) -> [Float] {
        let n = Int(duration * Double(sr))
        var mix = [Double](repeating: 0, count: n)
        let fsr = Double(sr)

        for i in 0..<ratios.count {
            for detune in [-0.7, 0.7] {
                let f = fundamental * ratios[i] + detune * (1 + Double(i) * 0.4)
                let v = amplitudes[i] * 0.5
                let bloomAt = 0.15 + blooms[i] * 0.6
                let decayAt = 7 - Double(i) * 0.6
                addPartial(&mix, sr: fsr, freq: f, level: v, bloomAt: bloomAt, decayAt: decayAt)
            }
        }
        addMallet(&mix, sr: fsr)

        let peak = mix.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? 0.9 / peak : 0
        return mix.map { Float($0 * gain) }
    }

    /// One sine with WebAudio-style automation: pitch 1.2 % high at the strike → nominal in 0.5 s → −1.5 % at 6 s;
    /// gain 0 → 0.35·v (6 ms) → v (bloom) → exponential to silence at `decayAt`.
    private static func addPartial(_ out: inout [Double], sr: Double, freq f: Double, level v: Double,
                                   bloomAt: Double, decayAt: Double) {
        let n05 = Int(0.5 * sr), n6 = Int(6 * sr)
        let nAttack = Int(0.006 * sr), nBloom = Int(bloomAt * sr), nEnd = min(out.count, Int(decayAt * sr))
        let fMulAttack = pow(1 / 1.012, 1 / Double(n05))
        let fMulDrift = pow(0.985, 1 / Double(n6 - n05))
        let gMulDecay = pow(0.0001 / v, 1 / Double(max(1, nEnd - nBloom)))

        var freq = f * 1.012, phase = 0.0, gain = 0.0
        for s in 0..<nEnd {
            if s < nAttack {
                gain = 0.0001 + (v * 0.35 - 0.0001) * Double(s) / Double(nAttack)
            } else if s < nBloom {
                gain = v * 0.35 + (v - v * 0.35) * Double(s - nAttack) / Double(max(1, nBloom - nAttack))
            } else if s == nBloom {
                gain = v
            } else {
                gain *= gMulDecay
            }
            out[s] += sin(phase) * gain
            phase += 2 * .pi * freq / sr
            if phase > 2 * .pi { phase -= 2 * .pi }
            if s < n05 { freq *= fMulAttack } else if s < n6 { freq *= fMulDrift }
        }
    }

    /// 120 ms of decaying noise through a 320 Hz low-pass: the felt mallet hitting the brass.
    private static func addMallet(_ out: inout [Double], sr: Double) {
        let len = Int(0.12 * sr)
        var rng = SplitMix64(seed: 0x60_4E_47)
        // RBJ biquad low-pass
        let w0 = 2 * Double.pi * 320 / sr, q = 0.7071, alpha = sin(w0) / (2 * q), cw = cos(w0)
        let a0 = 1 + alpha
        let b0 = (1 - cw) / 2 / a0, b1 = (1 - cw) / a0, b2 = b0, a1 = -2 * cw / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for s in 0..<min(out.count, Int(0.5 * sr)) {
            let x = s < len ? (rng.nextUnit() * 2 - 1) * pow(1 - Double(s) / Double(len), 3) : 0
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            out[s] += y * 1.4
        }
    }

    /// 16-bit PCM mono WAV.
    public static func wavData(_ samples: [Float], sampleRate sr: Int = sampleRate) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataLen = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataLen); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataLen)
        d.reserveCapacity(d.count + samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32_767)
            u16(UInt16(bitPattern: v))
        }
        return d
    }
}

/// Small deterministic PRNG so the mallet noise is identical on every launch (and in tests).
struct SplitMix64: Equatable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
