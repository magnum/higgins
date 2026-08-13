import Foundation

final class OllamaClient: TextImproving {
    private let prompt: String
    private let model: String
    private let baseURL: URL?
    private let serverURL: String
    private let session: URLSession

    init(
        prompt: String,
        model: String,
        serverURL: String = AIModelConstants.defaultOllamaURL,
        session: URLSession = .shared
    ) {
        self.prompt = prompt
        self.model = model
        self.serverURL = serverURL
        self.baseURL = URL(string: serverURL)
        self.session = session
    }

    static func chatEndpoint(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/chat")
    }

    static func modelsEndpoint(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/tags")
    }

    static func fetchModels(
        serverURL: String = AIModelConstants.defaultOllamaURL,
        session: URLSession = .shared
    ) async throws -> [String] {
        guard let baseURL = URL(string: serverURL) else {
            throw AIServiceError.invalidURL(serverURL)
        }

        let request = URLRequest(url: modelsEndpoint(baseURL: baseURL))
        let response = try await AITransport.send(request, as: ModelsResponse.self, session: session)
        return response.models.map(\.name)
    }

    func improveText(_ text: String) async throws -> String {
        let request = try makeRequest(for: text)

        log("Sending Ollama request with model \(model)")
        let response = try await AITransport.send(request, as: OllamaResponse.self, session: session)
        let content = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        guard !TextImprovementInstructions.isRefusal(content) else {
            throw AIServiceError.refusal(content)
        }
        return content
    }

    func makeRequest(for text: String) throws -> URLRequest {
        guard let baseURL else {
            throw AIServiceError.invalidURL(serverURL)
        }

        let renderedPrompt = try TextImprovementInstructions.render(
            customPrompt: prompt,
            selection: text
        )

        var request = URLRequest(url: Self.chatEndpoint(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaRequest(
                model: model,
                prompt: TextImprovementInstructions.systemPrompt,
                text: renderedPrompt
            )
        )
        return request
    }
}

private struct OllamaRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let temperature = 0.7
    }

    let model: String
    let messages: [Message]
    let stream = false
    let options = Options()

    init(model: String, prompt: String, text: String) {
        self.model = model
        self.messages = [
            Message(role: "system", content: prompt),
            Message(role: "user", content: text)
        ]
    }
}

private struct OllamaResponse: Decodable {
    struct Message: Decodable {
        let content: String
    }

    let message: Message
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}
