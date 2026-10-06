import XCTest
@testable import GongCore

final class AppVersionTests: XCTestCase {
    func testParsesTagsWithAndWithoutV() {
        XCTAssertEqual(AppVersion("v1.2.3")?.parts, [1, 2, 3])
        XCTAssertEqual(AppVersion("1.2")?.parts, [1, 2])
        XCTAssertEqual(AppVersion(" V2 ")?.parts, [2])
    }

    func testRejectsNonVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion("1.2.3-beta"))
    }

    func testComparesNumericallyAndPadsMissingParts() {
        XCTAssertLessThan(AppVersion("1.9.0")!, AppVersion("1.10.0")!)
        XCTAssertLessThan(AppVersion("1.0.0")!, AppVersion("v1.0.1")!)
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertFalse(AppVersion("2.0.0")! < AppVersion("1.9.9")!)
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    let api = URL(string: "https://api.github.com/repos/example/gong/releases/latest")!

    func release(_ tag: String) -> String {
        #"{"tag_name":"\#(tag)","html_url":"https://github.com/example/gong/releases/tag/\#(tag)","draft":false,"prerelease":false}"#
    }

    func testNewerReleaseIsAvailable() async {
        let checker = UpdateChecker(currentVersion: "1.0.0", apiURL: api, session: StubSession.make(status: 200, body: release("v1.1.0")))
        await checker.check()
        XCTAssertEqual(checker.available?.version, "1.1.0")
        XCTAssertEqual(checker.available?.pageURL.absoluteString, "https://github.com/example/gong/releases/tag/v1.1.0")
    }

    func testSameOrOlderReleaseIsNotAvailable() async {
        for tag in ["v1.0.0", "1.0", "v0.9.9"] {
            let checker = UpdateChecker(currentVersion: "1.0.0", apiURL: api, session: StubSession.make(status: 200, body: release(tag)))
            await checker.check()
            XCTAssertNil(checker.available, tag)
        }
    }

    func testFailuresKeepThePreviousResult() async {
        let checker = UpdateChecker(currentVersion: "1.0.0", apiURL: api, session: StubSession.make(status: 200, body: release("v1.1.0")))
        await checker.check()
        XCTAssertEqual(checker.available?.version, "1.1.0")
        // StubSession's response is global, so re-making it changes what the same session answers next.
        for (status, body) in [(404, "{}"), (403, "rate limited"), (200, "not json"), (200, release("nightly"))] {
            _ = StubSession.make(status: status, body: body)
            await checker.check()
            XCTAssertEqual(checker.available?.version, "1.1.0", "\(status) \(body)")
        }
    }

    func testUnknownCurrentVersionNeverOffersAnUpdate() async {
        let checker = UpdateChecker(currentVersion: "dev", apiURL: api, session: StubSession.make(status: 200, body: release("v9.0.0")))
        await checker.check()
        XCTAssertNil(checker.available)
    }

    func testCheckIsDueOncePerDay() {
        var now = utc("2026-10-06T09:00:00Z")
        let checker = UpdateChecker(currentVersion: "1.0.0", apiURL: api, now: { now })
        XCTAssertTrue(checker.isDue)
        checker.lastCheck = now
        now = now.addingTimeInterval(23 * 3600)
        XCTAssertFalse(checker.isDue)
        now = now.addingTimeInterval(3600)
        XCTAssertTrue(checker.isDue)
    }

    func testUpdateCommandRunsInTheClonedFolder() {
        XCTAssertEqual(UpdateChecker.updateCommand(sourcePath: "/Users/alex/Code/gong"),
                       "cd '/Users/alex/Code/gong' && git pull && scripts/build-app.sh --install && open /Applications/Gong.app")
        XCTAssertEqual(UpdateChecker.updateCommand(sourcePath: "/Users/alex/it's here"),
                       #"cd '/Users/alex/it'\''s here' && git pull && scripts/build-app.sh --install && open /Applications/Gong.app"#)
        XCTAssertEqual(UpdateChecker.updateCommand(sourcePath: nil),
                       "git pull && scripts/build-app.sh --install && open /Applications/Gong.app")
    }
}
