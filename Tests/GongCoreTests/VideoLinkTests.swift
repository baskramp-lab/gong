import XCTest
@testable import GongCore

final class VideoLinkTests: XCTestCase {
    func find(_ text: String) -> URL? { VideoLink.find(conference: nil, description: text, location: nil) }

    func testFindsKnownHostsAndSubdomains() {
        XCTAssertEqual(find("Join: https://meet.google.com/abc-defg-hij")?.host, "meet.google.com")
        XCTAssertEqual(find("https://us02web.zoom.us/j/123")?.host, "us02web.zoom.us")
        XCTAssertEqual(find("https://teams.microsoft.com/l/meetup-join/x")?.host, "teams.microsoft.com")
        XCTAssertEqual(find("https://teams.cloud.microsoft/meet/123")?.host, "teams.cloud.microsoft", "new Teams domain")
    }

    func testRejectsLookAlikeHosts() {
        XCTAssertNil(find("https://evilzoom.us/j/1"))
        XCTAssertNil(find("https://meet.google.com.evil.example/abc"))
    }

    func testRejectsNonWebSchemes() {
        for bad in ["smb://zoom.us/share", "file://zoom.us/etc/passwd", "x-evil://zoom.us/a", "vnc://zoom.us", "ssh://zoom.us"] {
            XCTAssertNil(find("Location: \(bad)"), bad)
        }
        XCTAssertNil(VideoLink.find(conference: "smb://meet.google.com/x", description: nil, location: nil))
    }

    func testIsSafeToOpen() {
        XCTAssertTrue(VideoLink.isWeb(URL(string: "https://meet.google.com/x")!))
        XCTAssertTrue(VideoLink.isWeb(URL(string: "HTTP://zoom.us/j/1")!))
        XCTAssertFalse(VideoLink.isWeb(URL(string: "smb://zoom.us/share")!))
        XCTAssertFalse(VideoLink.isWeb(URL(string: "file:///etc/passwd")!))
    }
}
