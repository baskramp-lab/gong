import XCTest
@testable import GongCore

final class GameSoundsTests: XCTestCase {
    func testShortAndNormalised() {
        for (name, s, maxLen) in [("tink", GameSounds.tink(), 0.2), ("tok", GameSounds.tok(), 0.15)] {
            XCTAssertLessThanOrEqual(Double(s.count) / 44_100, maxLen, name)
            XCTAssertEqual(s.reduce(0) { max($0, abs($1)) }, 0.9, accuracy: 0.001, name)
            XCTAssertLessThan(abs(s.last!), 0.01, "\(name) fades out")
        }
    }
    func testDeterministic() { XCTAssertEqual(GameSounds.tok(), GameSounds.tok()) }
}
