import Foundation

final class OpenAIClient: TextImproving {
    private let apiKey: String
    private let prompt: String
    private let model: String
    private let baseURL: URL?
    private let serverURL: String
    private let session: URLSession

    init(
        apiKey: String,
        prompt: String,
        model: String = AIModelConstants.defaultOpenAIModel,
        serverURL: String = AIModelConstants.defaultOpenAIBaseURL,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.prompt = prompt
        self.model = model
        self.serverURL = serverURL
        self.baseURL = URL(string: serverURL)
        self.session = session
    }

    static func chatEndpoint(baseURL: URL) -> URL {
        if baseURL.pathComponents.last == "v1" {
            return baseURL.appendingPathComponent("chat/completions")
        }
        return baseURL.appendingPathComponent("v1/chat/completions")
    }

    func improveText(_ text: String) async throws -> String {
        try await responseText(for: makeRequest(for: text))
    }

    private func responseText(for request: URLRequest) async throws -> String {
        log("Sending OpenAI request with model \(model)")
        let response = try await AITransport.send(request, as: ChatResponse.self, session: session)
        if let refusal = response.choices.first?.message.refusal {
            throw AIServiceError.refusal(refusal)
        }
        guard let rawContent = response.choices.first?.message.content else {
            throw AIServiceError.emptyResponse
        }
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        guard !TextImprovementInstructions.isRefusal(content) else {
            throw AIServiceError.refusal(content)
        }
        return content
    }

    func makeRequest(for text: String) throws -> URLRequest {
        let renderedPrompt = try TextImprovementInstructions.render(
            customPrompt: prompt,
            selection: text
        )

        return try makeRequest(
            systemPrompt: TextImprovementInstructions.systemPrompt,
            userContent: renderedPrompt
        )
    }

    private func makeRequest(systemPrompt: String, userContent: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        guard let baseURL else {
            throw AIServiceError.invalidURL(serverURL)
        }

        var request = URLRequest(url: Self.chatEndpoint(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                prompt: systemPrompt,
                text: userContent
            )
        )
        return request
    }
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature = 0.7
    let maxTokens = 4096

    init(model: String, prompt: String, text: String) {
        self.model = model
        self.messages = [
            Message(role: "system", content: prompt),
            Message(role: "user", content: text)
        ]
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let refusal: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
