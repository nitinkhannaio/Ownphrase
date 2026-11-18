import XCTest
@testable import Ownphrase

final class LearningLoopTests: XCTestCase {
    func testAcceptedChoiceChangesNextRequestWithoutSendingPastDrafts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OwnStore(directory: dir)
        let original = "I was wondering if you might send the Acacia estimate."
        let accepted = RewriteOption(text: "Could you send the Acacia estimate?", lesson: "",
                                     preference: "direct requests", context: "Work")
        try store.record(original: original, accepted: accepted)
        let reopened = OwnStore(directory: dir)
        XCTAssertEqual(try reopened.history().first?.text, accepted.text)
        let request = try OpenAIClient.makeRequest(text: "Can we meet?", instruction: "", profile: reopened.profile(), key: "fixture")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("direct requests"))
        XCTAssertFalse(body.contains("Acacia"))
        XCTAssertTrue(try reopened.daily().isEmpty)
    }
}
