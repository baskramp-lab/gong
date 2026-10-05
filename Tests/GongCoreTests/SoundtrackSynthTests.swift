import XCTest
@testable import GongCore

final class SoundtrackSynthTests: XCTestCase {
    static let samples = SoundtrackSynth.render()

    func testLoopIsWholeStrikeCycles() {
        let cycles = SoundtrackSynth.duration / StrikeClock.cycle
        XCTAssertEqual(cycles, cycles.rounded(), accuracy: 1e-9, "the loop stays in step with the strikes")
        XCTAssertEqual(Self.samples.count, Int(SoundtrackSynth.duration * Double(SoundtrackSynth.sampleRate)))
    }

    func testInScaleOnD() {
        XCTAssertEqual(SoundtrackSynth.frequency(degree: 0), 293.66, accuracy: 0.01)
        XCTAssertEqual(SoundtrackSynth.frequency(degree: 5), 587.32, accuracy: 0.01)
        XCTAssertEqual(SoundtrackSynth.frequency(degree: -5), 146.83, accuracy: 0.01)
        XCTAssertEqual(SoundtrackSynth.frequency(degree: 1), 293.66 * pow(2, 1.0 / 12), accuracy: 0.01) // E♭
    }

    func testPatternsFillWholeBars() {
        XCTAssertEqual(SoundtrackSynth.lead.count, SoundtrackSynth.bars * SoundtrackSynth.stepsPerBar)
        XCTAssertEqual(SoundtrackSynth.bass.count, SoundtrackSynth.bars)
        XCTAssertEqual(SoundtrackSynth.bars * SoundtrackSynth.stepsPerBar % SoundtrackSynth.koto.count, 0)
        XCTAssertEqual(SoundtrackSynth.bars * SoundtrackSynth.stepsPerBar % SoundtrackSynth.drums.count, 0)
    }

    func testHoldsExtendNotes() {
        let notes = SoundtrackSynth.notes("5-4.3---")
        XCTAssertEqual(notes.map(\.0.value), [5, 4, 3])
        XCTAssertEqual(notes.map(\.1), [2, 1, 4])
    }

    func testNormalisedAndAudibleThroughout() {
        let peak = Self.samples.reduce(0) { max($0, abs($1)) }
        XCTAssertEqual(peak, 0.9, accuracy: 0.001)
        let sec = SoundtrackSynth.sampleRate
        for k in 0..<Int(SoundtrackSynth.duration) {
            let slice = Self.samples[(k * sec)..<((k + 1) * sec)]
            let rms = (slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot()
            XCTAssertGreaterThan(rms, 0.01, "silent around \(k) s")
        }
    }

    func testDeterministic() {
        XCTAssertEqual(SoundtrackSynth.render(), Self.samples)
    }
}
