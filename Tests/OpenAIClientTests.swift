import XCTest
@testable import Ownphrase

final class OpenAIClientTests: XCTestCase {
    func testRequestCarriesOnlyCurrentPassageInstructionAndBoundedProfile() throws {
        let request = try OpenAIClient.makeRequest(text: "Meet at five", instruction: "Shorter",
                                                   profile: String(repeating: "x", count: 3500), key: "fixture")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? String)
        let payload = try JSONDecoder().decode([String: String].self, from: Data(input.utf8))
        XCTAssertEqual(Set(payload.keys), ["passage", "rewrite_instruction", "style_profile"])
        XCTAssertEqual(payload["style_profile"]?.count, 3000)
    }

    func testIncompleteAndRefusedResponsesCannotBeApplied() throws {
        for response in [
            #"{"status":"incomplete","output":[]}"#,
            #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#
        ] {
            XCTAssertThrowsError(try OpenAIClient.decode(Data(response.utf8), status: 200))
        }
        XCTAssertThrowsError(try OpenAIClient.decode(Data(), status: 429))
    }

    func testCompletedOptionsAreDecoded() throws {
        let option = RewriteOption(text: "Meet at five.", lesson: "", preference: "", context: "Casual")
        let json = try JSONEncoder().encode(["options": [option, option]])
        let body: [String: Any] = ["status": "completed", "output": [["type": "message", "content":
            [["type": "output_text", "text": String(decoding: json, as: UTF8.self)]]]]]
        XCTAssertEqual(try OpenAIClient.decode(JSONSerialization.data(withJSONObject: body), status: 200), [option])
    }
}
