import Foundation

enum AIBackendType: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case ollama = "ollama"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .ollama:
            "Ollama (Local)"
        }
    }
}

enum AIModelConstants {
    static let defaultOpenAIModel = "gpt-4o-mini"
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOllamaURL = "http://localhost:11434"
}
