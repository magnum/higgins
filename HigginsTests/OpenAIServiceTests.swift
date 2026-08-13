import XCTest
@testable import Higgins

final class OpenAIClientTests: XCTestCase {
    func testOpenAIEndpointWithV1BaseURL() {
        let baseURL = URL(string: "https://api.openai.com/v1")!
        let endpoint = OpenAIClient.chatEndpoint(baseURL: baseURL)
        XCTAssertEqual(endpoint.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testOpenAIEndpointWithBareBaseURL() {
        let baseURL = URL(string: "https://api.openai.com")!
        let endpoint = OpenAIClient.chatEndpoint(baseURL: baseURL)
        XCTAssertEqual(endpoint.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testOpenAIEndpointWithCustomBaseURL() {
        let baseURL = URL(string: "http://localhost:1234")!
        let endpoint = OpenAIClient.chatEndpoint(baseURL: baseURL)
        XCTAssertEqual(endpoint.absoluteString, "http://localhost:1234/v1/chat/completions")
    }

    func testOllamaEndpoint() {
        let baseURL = URL(string: "http://localhost:11434")!
        let endpoint = OllamaClient.chatEndpoint(baseURL: baseURL)
        XCTAssertEqual(endpoint.absoluteString, "http://localhost:11434/api/chat")
    }

    func testOllamaModelsEndpoint() {
        let baseURL = URL(string: "http://localhost:11434/")!
        let endpoint = OllamaClient.modelsEndpoint(baseURL: baseURL)
        XCTAssertEqual(endpoint.absoluteString, "http://localhost:11434/api/tags")
    }

    func testOpenAIRequestInsertsSelectionOnlyInsidePromptTemplate() throws {
        let client = OpenAIClient(
            apiKey: "test-key",
            prompt: "Custom editing rule:\n{selection}\nEnd of source.",
            serverURL: "https://api.openai.com/v1"
        )
        let request = try client.makeRequest(for: "Original text")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(payload["model"] as? String, AIModelConstants.defaultOpenAIModel)

        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(
            messages[0],
            ["role": "system", "content": TextImprovementInstructions.systemPrompt]
        )
        XCTAssertEqual(
            messages[1],
            ["role": "user", "content": "Custom editing rule:\nOriginal text\nEnd of source."]
        )
        XCTAssertFalse(messages[0]["content"]?.contains("Original text") == true)
    }

    func testEmptyCustomPromptFallsBackToDefaultTemplate() throws {
        let prompt = try TextImprovementInstructions.render(
            customPrompt: "   ",
            selection: "Original text"
        )

        XCTAssertTrue(prompt.contains("Original text"))
        XCTAssertFalse(prompt.contains(TextImprovementInstructions.selectionPlaceholder))
        XCTAssertTrue(
            TextImprovementInstructions.defaultPrompt.contains(
                TextImprovementInstructions.selectionPlaceholder
            )
        )
    }

    func testKnownRefusalResponseIsDetected() {
        XCTAssertTrue(
            TextImprovementInstructions.isRefusal("I'm sorry, but I cannot assist with that.")
        )
        XCTAssertTrue(
            TextImprovementInstructions.isRefusal("I apologize, but I am unable to assist with that.")
        )
        XCTAssertFalse(TextImprovementInstructions.isRefusal("This is the improved text."))
    }

    func testPromptWithoutSelectionPlaceholderThrows() {
        let client = OpenAIClient(
            apiKey: "test-key",
            prompt: "A custom instruction without a placeholder",
            serverURL: "https://api.openai.com/v1"
        )

        XCTAssertThrowsError(try client.makeRequest(for: "Original text")) { error in
            guard case AIServiceError.missingSelectionPlaceholder = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testOllamaRequestUsesTheSamePromptTemplate() throws {
        let client = OllamaClient(
            prompt: "Rewrite only this value: {selection}",
            model: "test-model"
        )

        let request = try client.makeRequest(for: "Original text")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1], [
            "role": "user",
            "content": "Rewrite only this value: Original text"
        ])
        XCTAssertFalse(messages[0]["content"]?.contains("Original text") == true)
    }
}
