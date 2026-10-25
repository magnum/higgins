import Foundation

final class AnthropicClient: TextImproving {
    private static let apiVersion = "2023-06-01"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that accept server-side `fallbacks: "default"`, which retries a
    /// safety-classifier refusal on another model instead of returning it.
    private static let modelsWithFallbacks: Set<String> = [
        "claude-fable-5-1",
        "claude-opus-5-5",
        "claude-opus-5",
        "claude-sonnet-5-5"
    ]

    private let apiKey: String
    private let prompt: String
    private let model: String
    private let session: URLSession

    init(
        apiKey: String,
        prompt: String,
        model: String = AIModelConstants.defaultAnthropicModel,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.prompt = prompt
        self.model = model
        self.session = session
    }

    static func fetchModels(apiKey: String, session: URLSession = .shared) async throws -> [String] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        guard var components = URLComponents(string: "\(AIModelConstants.anthropicBaseURL)/models") else {
            throw AIServiceError.invalidURL(AIModelConstants.anthropicBaseURL)
        }
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        guard let url = components.url else {
            throw AIServiceError.invalidURL(AIModelConstants.anthropicBaseURL)
        }

        var request = URLRequest(url: url)
        setHeaders(on: &request, apiKey: apiKey)
        let response = try await AITransport.send(request, as: ModelsResponse.self, session: session)
        return response.data.map(\.id)
    }

    func improveText(_ text: String) async throws -> String {
        let request = try makeRequest(for: text)

        log("Sending Anthropic request with model \(model)")
        let response = try await AITransport.send(request, as: MessagesResponse.self, session: session)
        // Check the stop reason before reading content: a refusal may arrive with no text.
        guard response.stopReason != "refusal" else {
            throw AIServiceError.refusal("The request was declined by the model's safety system.")
        }
        let content = response.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        guard !TextImprovementInstructions.isRefusal(content) else {
            throw AIServiceError.refusal(content)
        }
        return content
    }

    func makeRequest(for text: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        guard let url = URL(string: "\(AIModelConstants.anthropicBaseURL)/messages") else {
            throw AIServiceError.invalidURL(AIModelConstants.anthropicBaseURL)
        }

        let renderedPrompt = try TextImprovementInstructions.render(
            customPrompt: prompt,
            selection: text
        )
        let usesFallbacks = Self.modelsWithFallbacks.contains(model)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        Self.setHeaders(on: &request, apiKey: apiKey)
        if usesFallbacks {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(
            MessagesRequest(
                model: model,
                system: TextImprovementInstructions.systemPrompt,
                text: renderedPrompt,
                fallbacks: usesFallbacks ? "default" : nil
            )
        )
        return request
    }

    private static func setHeaders(on request: inout URLRequest, apiKey: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
    }
}

private struct MessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens = 16000
    let system: String
    let messages: [Message]
    let fallbacks: String?

    init(model: String, system: String, text: String, fallbacks: String?) {
        self.model = model
        self.system = system
        self.messages = [Message(role: "user", content: text)]
        self.fallbacks = fallbacks
    }

    enum CodingKeys: String, CodingKey {
        case model, system, messages, fallbacks
        case maxTokens = "max_tokens"
    }
}

private struct MessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
