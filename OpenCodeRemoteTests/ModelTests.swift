import XCTest
@testable import OpenCodeRemote

final class ModelTests: XCTestCase {

    private func part(id: String, text: String? = nil, status: String? = nil, output: String? = nil) -> OCPart {
        let state: OCToolState? = (status != nil || output != nil)
            ? OCToolState(status: status, title: nil, output: output, input: nil, time: nil, metadata: nil)
            : nil
        return OCPart(id: id, type: "text", text: text, tool: nil, callID: nil,
                      state: state, mime: nil, filename: nil, url: nil)
    }

    // MARK: - OCPart.isContentEqual

    func testPartEqualWhenIdentical() {
        let a = part(id: "p1", text: "hello")
        let b = part(id: "p1", text: "hello")
        XCTAssertTrue(a.isContentEqual(to: b))
    }

    func testPartNotEqualWhenTextDiffers() {
        let a = part(id: "p1", text: "hello")
        let b = part(id: "p1", text: "hello world")
        XCTAssertFalse(a.isContentEqual(to: b))
    }

    func testPartNotEqualWhenStatusChanges() {
        let a = part(id: "p1", status: "running")
        let b = part(id: "p1", status: "completed")
        XCTAssertFalse(a.isContentEqual(to: b), "Đổi status tool phải coi là khác để UI cập nhật")
    }

    func testPartNotEqualWhenOutputChanges() {
        let a = part(id: "p1", status: "completed", output: "")
        let b = part(id: "p1", status: "completed", output: "done")
        XCTAssertFalse(a.isContentEqual(to: b))
    }

    func testStableIDUsesIdWhenPresent() {
        let p = part(id: "abc")
        XCTAssertEqual(p.stableID, "abc")
    }

    func testStableIDFallsBackToTypeAndCallID() {
        let p = OCPart(id: nil, type: "tool", text: nil, tool: "bash", callID: "call42",
                       state: nil, mime: nil, filename: nil, url: nil)
        XCTAssertEqual(p.stableID, "tool_call42")
    }

    // MARK: - OCMessageWithParts.isContentEqual

    private func message(id: String, role: String = "assistant", parts: [OCPart]) -> OCMessageWithParts {
        OCMessageWithParts(
            info: OCMessage(id: id, role: role, sessionID: "s1", time: nil,
                            providerID: nil, modelID: nil, agent: nil, error: nil),
            parts: parts
        )
    }

    func testMessageEqualWhenSamePartsAndInfo() {
        let a = message(id: "m1", parts: [part(id: "p1", text: "x")])
        let b = message(id: "m1", parts: [part(id: "p1", text: "x")])
        XCTAssertTrue(a.isContentEqual(to: b))
    }

    func testMessageNotEqualWhenPartCountDiffers() {
        let a = message(id: "m1", parts: [part(id: "p1", text: "x")])
        let b = message(id: "m1", parts: [part(id: "p1", text: "x"), part(id: "p2", text: "y")])
        XCTAssertFalse(a.isContentEqual(to: b))
    }

    func testMessageNotEqualWhenPartContentDiffers() {
        let a = message(id: "m1", parts: [part(id: "p1", text: "x")])
        let b = message(id: "m1", parts: [part(id: "p1", text: "changed")])
        XCTAssertFalse(a.isContentEqual(to: b))
    }

    func testMessageNotEqualWhenIdDiffers() {
        let a = message(id: "m1", parts: [part(id: "p1", text: "x")])
        let b = message(id: "m2", parts: [part(id: "p1", text: "x")])
        XCTAssertFalse(a.isContentEqual(to: b))
    }

    func testMessageIdFallsBackToStableLocalID() {
        let m = OCMessageWithParts(
            info: OCMessage(id: nil, role: "user", sessionID: nil, time: nil,
                            providerID: nil, modelID: nil, agent: nil, error: nil),
            parts: []
        )
        // id rỗng -> dùng localStableID ổn định (không đổi giữa các lần truy cập).
        XCTAssertEqual(m.id, m.id)
        XCTAssertFalse(m.id.isEmpty)
    }

    // MARK: - OCSession

    func testSessionDisplayTitleFallback() {
        let s = OCSession(id: "abcdef123456", title: nil, slug: nil, directory: nil,
                          model: nil, agent: nil, time: nil)
        XCTAssertEqual(s.displayTitle, "Phiên #abcdef12")
    }

    func testSessionDisplayTitleUsesTitle() {
        let s = OCSession(id: "x", title: "Build app", slug: nil, directory: nil,
                          model: nil, agent: nil, time: nil)
        XCTAssertEqual(s.displayTitle, "Build app")
    }

    func testSessionLastActivityPrefersUpdated() {
        let s = OCSession(id: "x", title: nil, slug: nil, directory: nil, model: nil, agent: nil,
                          time: OCTime(created: 100, updated: 200, completed: nil, start: nil, end: nil))
        XCTAssertEqual(s.lastActivity, 200)
    }

    // MARK: - OCJSONValue.displayString

    func testJSONValueDisplayString() {
        XCTAssertEqual(OCJSONValue.string("hi").displayString, "hi")
        XCTAssertEqual(OCJSONValue.bool(true).displayString, "true")
        XCTAssertEqual(OCJSONValue.number(3).displayString, "3")
        XCTAssertEqual(OCJSONValue.null.displayString, "")
    }
}
