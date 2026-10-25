import Foundation
import Observation

@MainActor
@Observable
final class SettingsService {
    struct Prompt: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var content: String

        init(id: UUID = UUID(), name: String, content: String) {
            self.id = id
            self.name = name
            self.content = content
        }
    }

    static let defaultPrompt = TextImprovementInstructions.defaultPrompt

    var openAIKey: String {
        didSet { persistAPIKey(openAIKey, account: Key.openAIKey) }
    }

    var anthropicKey: String {
        didSet { persistAPIKey(anthropicKey, account: Key.anthropicKey) }
    }

    var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: Key.openAIBaseURL) }
    }

    var aiBackend: AIBackendType {
        didSet { defaults.set(aiBackend.rawValue, forKey: Key.aiBackend) }
    }

    var ollamaURL: String {
        didSet { defaults.set(ollamaURL, forKey: Key.ollamaURL) }
    }

    /// Each backend remembers its own model, so switching provider keeps the choice.
    private(set) var models: [AIBackendType: String] {
        didSet {
            for (backend, model) in models {
                defaults.set(model, forKey: Key.model(for: backend))
            }
        }
    }

    /// The model of the currently selected backend.
    var selectedModel: String {
        get { models[aiBackend] ?? aiBackend.defaultModel }
        set { models[aiBackend] = newValue }
    }

    private(set) var prompts: [Prompt] {
        didSet { persistPrompts() }
    }

    private(set) var selectedPromptID: Prompt.ID {
        didSet { defaults.set(selectedPromptID.uuidString, forKey: Key.selectedPromptID) }
    }

    var selectedPromptIndex: Int {
        prompts.firstIndex { $0.id == selectedPromptID } ?? 0
    }

    var selectedPromptName: String {
        prompts[selectedPromptIndex].name
    }

    var improvementPrompt: String {
        get { prompts[selectedPromptIndex].content }
        set {
            prompts[selectedPromptIndex].content = newValue
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainService
    @ObservationIgnored private var isLoadingAPIKeys = false

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.openAIBaseURL = defaults.string(forKey: Key.openAIBaseURL)
            ?? AIModelConstants.defaultOpenAIBaseURL
        let backend = defaults.string(forKey: Key.aiBackend)
            .flatMap(AIBackendType.init(rawValue:)) ?? .openAI
        self.aiBackend = backend
        self.ollamaURL = defaults.string(forKey: Key.ollamaURL)
            ?? AIModelConstants.defaultOllamaURL
        self.models = Self.loadModels(from: defaults, legacyBackend: backend)

        let loadedPrompts = Self.loadPrompts(from: defaults)
        let effectivePrompts = loadedPrompts.isEmpty
            ? [Prompt(name: "Default", content: Self.defaultPrompt)]
            : loadedPrompts
        let storedID = defaults.string(forKey: Key.selectedPromptID).flatMap(UUID.init(uuidString:))
        let effectivePromptID = storedID.flatMap { id in
            effectivePrompts.contains { $0.id == id } ? id : nil
        } ?? effectivePrompts[0].id

        self.prompts = effectivePrompts
        self.selectedPromptID = effectivePromptID
        self.openAIKey = ""
        self.anthropicKey = ""

        loadAPIKeys()
        persistPrompts()
        log("Settings loaded")
    }

    func selectPrompt(id: Prompt.ID) {
        guard prompts.contains(where: { $0.id == id }) else { return }
        selectedPromptID = id
    }

    func addPrompt(named name: String, content: String) {
        let prompt = Prompt(name: name, content: content)
        prompts.append(prompt)
        selectedPromptID = prompt.id
    }

    func removeSelectedPrompt() {
        guard prompts.count > 1 else { return }
        let removedIndex = selectedPromptIndex
        prompts.remove(at: removedIndex)
        selectedPromptID = prompts[min(removedIndex, prompts.count - 1)].id
    }

    func renameSelectedPrompt(to name: String) {
        prompts[selectedPromptIndex].name = name
    }

    func containsPrompt(named name: String, excluding id: Prompt.ID? = nil) -> Bool {
        prompts.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func loadAPIKeys() {
        isLoadingAPIKeys = true
        defer { isLoadingAPIKeys = false }

        do {
            anthropicKey = try keychain.get(Key.anthropicKey) ?? ""
        } catch {
            log("Failed to load the Anthropic API key: \(error.localizedDescription)", type: .error)
        }

        let legacyKey = defaults.string(forKey: Key.openAIKey) ?? ""
        if !legacyKey.isEmpty {
            openAIKey = legacyKey
            defaults.removeObject(forKey: Key.openAIKey)
            isLoadingAPIKeys = false
            persistAPIKey(openAIKey, account: Key.openAIKey)
            return
        }

        do {
            openAIKey = try keychain.get(Key.openAIKey) ?? ""
        } catch {
            log("Failed to load the OpenAI API key: \(error.localizedDescription)", type: .error)
        }
    }

    private func persistAPIKey(_ value: String, account: String) {
        guard !isLoadingAPIKeys else { return }
        do {
            if value.isEmpty {
                try keychain.delete(account)
            } else {
                try keychain.set(value, for: account)
            }
        } catch {
            log("Failed to save the API key (\(account)): \(error.localizedDescription)", type: .error)
        }
    }

    private static func loadModels(
        from defaults: UserDefaults,
        legacyBackend: AIBackendType
    ) -> [AIBackendType: String] {
        // Before per-backend models, a single model was shared by whichever backend was active.
        let legacyModel = defaults.string(forKey: Key.legacySelectedModel)
        var models: [AIBackendType: String] = [:]
        for backend in AIBackendType.allCases {
            models[backend] = defaults.string(forKey: Key.model(for: backend))
                ?? (backend == legacyBackend ? legacyModel : nil)
                ?? backend.defaultModel
        }
        return models
    }

    private func persistPrompts() {
        do {
            defaults.set(try JSONEncoder().encode(prompts), forKey: Key.prompts)
        } catch {
            log("Failed to save prompts: \(error.localizedDescription)", type: .error)
        }
    }

    private static func loadPrompts(from defaults: UserDefaults) -> [Prompt] {
        if let data = defaults.data(forKey: Key.prompts),
           let prompts = try? JSONDecoder().decode([Prompt].self, from: data) {
            return prompts
        }

        guard let promptData = defaults.data(forKey: Key.legacyPrompts),
              let contents = try? JSONDecoder().decode([String].self, from: promptData) else {
            return []
        }
        let names = defaults.data(forKey: Key.legacyPromptNames)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return contents.enumerated().map { index, content in
            Prompt(
                name: names.indices.contains(index) ? names[index] : "Prompt \(index + 1)",
                content: content
            )
        }
    }

    private enum Key {
        static let openAIKey = "openaiKey"
        static let anthropicKey = "anthropicKey"
        static let openAIBaseURL = "openaiBaseURL"
        static let aiBackend = "aiBackend"
        static let ollamaURL = "ollamaURL"
        static let legacySelectedModel = "selectedModel"
        static let prompts = "prompts.v2"
        static let selectedPromptID = "selectedPromptID"
        static let legacyPrompts = "promptsData"
        static let legacyPromptNames = "promptNamesData"

        static func model(for backend: AIBackendType) -> String {
            "selectedModel.\(backend.rawValue)"
        }
    }
}
