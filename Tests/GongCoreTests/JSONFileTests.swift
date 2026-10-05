import XCTest
@testable import GongCore

final class JSONFileTests: XCTestCase {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gong-tests-\(UUID().uuidString)/sub/file.json")
    }

    func testLoadReturnsDefaultWhenMissing() {
        let f = JSONFile<AppSettings>(url: tempURL())
        XCTAssertEqual(f.load(default: .default), .default)
    }

    func testSaveCreatesDirectoriesAndRoundTrips() throws {
        let f = JSONFile<PersistedState>(url: tempURL())
        let state = PersistedState(states: ["a": .snoozed(until: utc("2026-09-28T12:00:00Z"))], pauseUntil: utc("2026-09-28T13:00:00Z"))
        try f.save(state)
        XCTAssertEqual(f.load(default: PersistedState()), state)
    }

    func testCorruptFileFallsBackToDefault() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(JSONFile<AppSettings>(url: url).load(default: .default), .default)
    }

    func testSettingsDefaultsMatchSpec() {
        let s = AppSettings.default
        XCTAssertEqual(s.softMinutes, [30, 10]); XCTAssertEqual(s.hardMinutes, 5)
        XCTAssertEqual(s.snoozeMinutes, 2); XCTAssertEqual(s.lateGraceMinutes, 15)
        XCTAssertTrue(s.soundEnabled); XCTAssertEqual(s.refreshMinutes, 5); XCTAssertEqual(s.staleMinutes, 15)
        XCTAssertEqual(s.schedulerConfig, SchedulerConfig(softMinutes: [30, 10], hardMinutes: 5, snoozeMinutes: 2, lateGraceMinutes: 15))
    }

    func testSettingsDecodeWithMissingKeysUsesDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{\"soundEnabled\":false}".utf8))
        XCTAssertFalse(s.soundEnabled)
        XCTAssertEqual(s.hardMinutes, 5)
    }

    func testUpdateKeepsOtherFieldsAndHandEdits() throws {
        let url = tempURL()
        let f = JSONFile<AppSettings>(url: url)
        var s = AppSettings.default
        s.hardMinutes = 7
        try f.save(s)                                   // "hand edit" made while the app runs
        let saved = f.update(default: .default) { $0.soundEnabled = false }
        XCTAssertEqual(saved?.hardMinutes, 7)
        XCTAssertEqual(saved?.soundEnabled, false)
        XCTAssertEqual(f.load(default: .default).hardMinutes, 7)
    }

    func testUpdateNeverOverwritesACorruptFile() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("{\"hardMinutes\": \"7\"}".utf8)   // wrong type
        try broken.write(to: url)
        XCTAssertNil(JSONFile<AppSettings>(url: url).update(default: .default) { $0.soundEnabled = false })
        XCTAssertEqual(try Data(contentsOf: url), broken, "file left untouched")
    }

    func testUpdateCreatesAMissingFile() {
        let f = JSONFile<AppSettings>(url: tempURL())
        XCTAssertEqual(f.update(default: .default) { $0.bestGameScore = 50 }?.bestGameScore, 50)
        XCTAssertEqual(f.load(default: .default).bestGameScore, 50)
    }
}
