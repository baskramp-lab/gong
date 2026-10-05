import XCTest
@testable import GongCore

final class GongSynthTests: XCTestCase {
    static let samples = GongSynth.render()

    private func rms(_ s: ArraySlice<Float>) -> Float {
        (s.reduce(0) { $0 + $1 * $1 } / Float(s.count)).squareRoot()
    }

    func testLengthIsSevenSeconds() {
        XCTAssertEqual(Self.samples.count, 7 * 44_100)
    }

    func testNormalizedPeak() {
        let peak = Self.samples.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.9 + 1e-5)
        XCTAssertGreaterThan(peak, 0.89)
    }

    func testDeterministic() {
        XCTAssertEqual(GongSynth.render(), Self.samples)
    }

    func testDecays() {
        let sr = 44_100
        let attack = rms(Self.samples[0..<(sr / 2)])
        let tail = rms(Self.samples[(Self.samples.count - sr / 2)...])
        XCTAssertGreaterThan(attack, tail * 20)
        XCTAssertGreaterThan(tail, 0, "should ring out, not cut off")
    }

    func testBloomPeaksAfterTheAttack() {
        // Higher partials swell in after the strike, so the loudest 50 ms window is not the very first one.
        let w = 2_205
        let windows = stride(from: 0, to: 44_100, by: w).map { rms(Self.samples[$0..<($0 + w)]) }
        XCTAssertGreaterThan(windows.firstIndex(of: windows.max()!)!, 0)
    }

    func testWavHeader() {
        let data = GongSynth.wavData(Self.samples)
        let bytes = [UInt8](data)
        func u32(_ o: Int) -> UInt32 { bytes[o..<(o + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func u16(_ o: Int) -> UInt16 { UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8 }
        XCTAssertEqual(String(bytes: bytes[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(bytes: bytes[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(bytes: bytes[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(u16(20), 1)       // PCM
        XCTAssertEqual(u16(22), 1)       // mono
        XCTAssertEqual(u32(24), 44_100)
        XCTAssertEqual(u16(34), 16)
        XCTAssertEqual(u32(40), UInt32(Self.samples.count * 2))
        XCTAssertEqual(data.count, 44 + Self.samples.count * 2)
        XCTAssertEqual(u32(4), UInt32(data.count - 8))
    }
}
