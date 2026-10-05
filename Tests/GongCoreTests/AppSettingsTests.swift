import XCTest
@testable import GongCore

final class AppSettingsTests: XCTestCase {
    func testIncludeUnacceptedDefaultsToTrue() {
        XCTAssertTrue(AppSettings.default.includeUnaccepted)
    }

    func testMissingKeyFallsBackToDefault() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{\"soundEnabled\":false}".utf8))
        XCTAssertTrue(decoded.includeUnaccepted)
        XCTAssertFalse(decoded.soundEnabled)
    }

    func testRoundTrip() throws {
        var s = AppSettings.default
        s.includeUnaccepted = false
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), s)
    }

    /// Settings files from older versions (with keys that no longer exist) still decode.
    func testOldKeysAreIgnored() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"soundName":"Glass","bestGameSeconds":83.5,"hardMinutes":7}"#.utf8))
        XCTAssertEqual(old.hardMinutes, 7)
    }

    func testBestGameScoreDefaultsAndRoundTrips() throws {
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).bestGameScore, 0)
        var s = AppSettings(); s.bestGameScore = 1234
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).bestGameScore, 1234)
    }
}
