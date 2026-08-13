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
        didSet { persistOpenAIKey() }
    }

    var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: Key.openAIBaseURL) }
    }

    var aiBackend: AIBackendType {
        didSet {
            defaults.set(aiBackend.rawValue, forKey: Key.aiBackend)
            if aiBackend == .openAI, oldValue != .openAI {
                selectedModel = AIModelConstants.defaultOpenAIModel
            }
        }
    }

    var ollamaURL: String {
        didSet { defaults.set(ollamaURL, forKey: Key.ollamaURL) }
    }

    var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: Key.selectedModel) }
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
    @ObservationIgnored private var isLoadingAPIKey = false

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.openAIBaseURL = defaults.string(forKey: Key.openAIBaseURL)
            ?? AIModelConstants.defaultOpenAIBaseURL
        self.aiBackend = defaults.string(forKey: Key.aiBackend)
            .flatMap(AIBackendType.init(rawValue:)) ?? .openAI
        self.ollamaURL = defaults.string(forKey: Key.ollamaURL)
            ?? AIModelConstants.defaultOllamaURL
        self.selectedModel = defaults.string(forKey: Key.selectedModel)
            ?? AIModelConstants.defaultOpenAIModel

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

        loadOpenAIKey()
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

    private func loadOpenAIKey() {
        isLoadingAPIKey = true
        defer { isLoadingAPIKey = false }

        let legacyKey = defaults.string(forKey: Key.openAIKey) ?? ""
        if !legacyKey.isEmpty {
            openAIKey = legacyKey
            defaults.removeObject(forKey: Key.openAIKey)
            persistOpenAIKey()
            return
        }

        do {
            openAIKey = try keychain.get(Key.openAIKey) ?? ""
        } catch {
            log("Failed to load the OpenAI API key: \(error.localizedDescription)", type: .error)
        }
    }

    private func persistOpenAIKey() {
        guard !isLoadingAPIKey else { return }
        do {
            if openAIKey.isEmpty {
                try keychain.delete(Key.openAIKey)
            } else {
                try keychain.set(openAIKey, for: Key.openAIKey)
            }
        } catch {
            log("Failed to save the OpenAI API key: \(error.localizedDescription)", type: .error)
        }
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
        static let openAIBaseURL = "openaiBaseURL"
        static let aiBackend = "aiBackend"
        static let ollamaURL = "ollamaURL"
        static let selectedModel = "selectedModel"
        static let prompts = "prompts.v2"
        static let selectedPromptID = "selectedPromptID"
        static let legacyPrompts = "promptsData"
        static let legacyPromptNames = "promptNamesData"
    }
}
