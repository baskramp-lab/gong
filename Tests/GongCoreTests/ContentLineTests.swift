import XCTest
@testable import GongCore

final class ContentLineTests: XCTestCase {
    func testUnfoldJoinsContinuationLines() {
        let text = "SUMMARY:Hello\r\n  World\r\nUID:1\r\n"
        XCTAssertEqual(ContentLine.unfold(text), ["SUMMARY:Hello World", "UID:1"])
    }

    func testUnfoldHandlesLFAndTab() {
        XCTAssertEqual(ContentLine.unfold("A:1\n\tb\nC:3"), ["A:1b", "C:3"])
    }

    func testParseSimple() {
        let cl = ContentLine.parse("summary:Refinement")!
        XCTAssertEqual(cl.name, "SUMMARY")
        XCTAssertEqual(cl.value, "Refinement")
        XCTAssertTrue(cl.params.isEmpty)
    }

    func testParseParamsAndMailtoValue() {
        let cl = ContentLine.parse("ATTENDEE;CUTYPE=INDIVIDUAL;PARTSTAT=ACCEPTED;CN=Alex Example:mailto:alex@example.com")!
        XCTAssertEqual(cl.name, "ATTENDEE")
        XCTAssertEqual(cl.params["PARTSTAT"], "ACCEPTED")
        XCTAssertEqual(cl.params["CN"], "Alex Example")
        XCTAssertEqual(cl.value, "mailto:alex@example.com")
    }

    func testParseQuotedParamWithColon() {
        let cl = ContentLine.parse("X-LOC;X-TITLE=\"Room: A\":geo:1,2")!
        XCTAssertEqual(cl.params["X-TITLE"], "Room: A")
        XCTAssertEqual(cl.value, "geo:1,2")
    }

    func testParseDTSTARTWithTZID() {
        let cl = ContentLine.parse("DTSTART;TZID=Europe/Amsterdam:20260928T140000")!
        XCTAssertEqual(cl.name, "DTSTART")
        XCTAssertEqual(cl.params["TZID"], "Europe/Amsterdam")
        XCTAssertEqual(cl.value, "20260928T140000")
    }

    func testParseReturnsNilWithoutColon() {
        XCTAssertNil(ContentLine.parse("NOCOLON"))
    }

    func testUnescape() {
        XCTAssertEqual(ContentLine.unescapeText("a\\nb\\, c\\; d\\\\e"), "a\nb, c; d\\e")
    }

    func testUnfoldWhenContinuationStartsWithCombiningMark() {
        XCTAssertEqual(ContentLine.unfold("SUMMARY:Cafe\n \u{301} bar\nUID:1"), ["SUMMARY:Cafe\u{301} bar", "UID:1"])
    }

    func testDecodeUnfoldsBytesBeforeUTF8() {
        let data = Data("SUMMARY:".utf8) + Data([0x41, 0xC3, 0x0D, 0x0A, 0x20, 0xA9]) + Data("\r\nUID:1\n\tx".utf8)
        XCTAssertEqual(ContentLine.decode(data), "SUMMARY:A\u{E9}\r\nUID:1x")
    }

    func testDecodeFallsBackToLossy() {
        let data = Data("SUMMARY:A".utf8) + Data([0xFF]) + Data("B".utf8)
        XCTAssertEqual(ContentLine.decode(data), "SUMMARY:A\u{FFFD}B")
    }
}
