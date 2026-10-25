import Foundation

enum AIBackendType: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case ollama = "ollama"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .ollama:
            "Ollama (Local)"
        }
    }

    /// Model used until the user picks one from the provider's model list.
    var defaultModel: String {
        switch self {
        case .openAI:
            AIModelConstants.defaultOpenAIModel
        case .anthropic:
            AIModelConstants.defaultAnthropicModel
        case .ollama:
            ""
        }
    }
}

enum AIModelConstants {
    static let defaultOpenAIModel = "gpt-4o-mini"
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultAnthropicModel = "claude-opus-5-5"
    static let anthropicBaseURL = "https://api.anthropic.com/v1"
    static let defaultOllamaURL = "http://localhost:11434"
}
