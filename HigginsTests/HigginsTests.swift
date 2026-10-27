import XCTest
@testable import Higgins

@MainActor
final class SettingsServiceTests: XCTestCase {
    func testPromptLifecycleMaintainsAValidSelection() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        let originalPromptID = settings.selectedPromptID
        settings.addPrompt(named: "Concise", content: "Be concise")

        XCTAssertEqual(settings.prompts.count, 2)
        XCTAssertEqual(settings.selectedPromptName, "Concise")
        XCTAssertNotEqual(settings.selectedPromptID, originalPromptID)

        settings.improvementPrompt = "Be very concise"
        settings.renameSelectedPrompt(to: "Short")

        XCTAssertEqual(settings.selectedPromptName, "Short")
        XCTAssertEqual(settings.improvementPrompt, "Be very concise")

        settings.removeSelectedPrompt()

        XCTAssertEqual(settings.prompts.count, 1)
        XCTAssertEqual(settings.selectedPromptID, originalPromptID)
    }

    func testPromptsPersistAcrossInstances() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.addPrompt(named: "Review", content: "Review this text")
        let selectedID = settings.selectedPromptID

        let reloaded = SettingsService(
            defaults: defaults,
            keychain: KeychainService(service: "\(suite).reloaded")
        )

        XCTAssertEqual(reloaded.prompts, settings.prompts)
        XCTAssertEqual(reloaded.selectedPromptID, selectedID)
        XCTAssertEqual(reloaded.improvementPrompt, "Review this text")
    }

    func testPromptNameLookupIsCaseInsensitive() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.addPrompt(named: "Review", content: "Review this text")

        XCTAssertTrue(settings.containsPrompt(named: "review"))
        XCTAssertFalse(settings.containsPrompt(named: "review", excluding: settings.selectedPromptID))
    }

    func testFreshSettingsNeedAISetupUntilVerifiedAndSaved() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(settings.aiBackend, .openAI)
        XCTAssertEqual(settings.selectedModel, AIModelConstants.defaultOpenAIModel)
        XCTAssertTrue(settings.needsAISetup)
        XCTAssertFalse(settings.hasRequiredAISettings)
        XCTAssertFalse(settings.saveAISettings(verifiedByTest: true))
        XCTAssertTrue(settings.needsAISetup)
    }

    func testAISettingsPersistWhenChangedAndRequireVerificationToSave() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.aiBackend = .anthropic
        settings.selectedModel = "claude-opus-5-5"
        settings.anthropicKey = "ant-key"

        XCTAssertTrue(settings.hasRequiredAISettings)
        XCTAssertTrue(settings.needsAISetup)
        XCTAssertFalse(settings.saveAISettings(verifiedByTest: false))
        XCTAssertTrue(settings.saveAISettings(verifiedByTest: true))
        XCTAssertFalse(settings.needsAISetup)

        let reloaded = SettingsService(
            defaults: defaults,
            keychain: KeychainService(service: suite)
        )

        XCTAssertEqual(reloaded.aiBackend, .anthropic)
        XCTAssertEqual(reloaded.selectedModel, "claude-opus-5-5")
        XCTAssertEqual(reloaded.anthropicKey, "ant-key")
        XCTAssertFalse(reloaded.needsAISetup)
    }

    func testOllamaSetupRequiresAModelButNotAnAPIKey() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.aiBackend = .ollama

        XCTAssertFalse(settings.hasRequiredAISettings)
        XCTAssertTrue(settings.needsAISetup)

        settings.selectedModel = "llama3"

        XCTAssertTrue(settings.hasRequiredAISettings)
        XCTAssertTrue(settings.saveAISettings(verifiedByTest: true))
        XCTAssertFalse(settings.needsAISetup)
    }

    func testClearingTheAPIKeyRequiresSetupAgain() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.openAIKey = "sk-test"
        XCTAssertTrue(settings.saveAISettings(verifiedByTest: true))
        XCTAssertFalse(settings.needsAISetup)

        settings.openAIKey = ""

        XCTAssertTrue(settings.needsAISetup)
        XCTAssertFalse(settings.hasVerifiedAISettings)
        XCTAssertFalse(settings.saveAISettings(verifiedByTest: true))

        settings.openAIKey = "sk-test"
        XCTAssertTrue(settings.needsAISetup)
        XCTAssertTrue(settings.saveAISettings(verifiedByTest: true))
        XCTAssertFalse(settings.needsAISetup)
    }

    func testSwitchingToABackendWithoutCredentialsRequiresSetupAgain() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.openAIKey = "sk-test"
        XCTAssertTrue(settings.saveAISettings(verifiedByTest: true))

        settings.aiBackend = .anthropic

        XCTAssertTrue(settings.needsAISetup)
        XCTAssertFalse(settings.hasVerifiedAISettings)
    }

    func testExistingCredentialsAreTreatedAsAlreadyVerified() throws {
        let suite = "HigginsTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let keychain = KeychainService(service: suite)
        try keychain.set("sk-existing", for: "openaiKey")
        defaults.set("openai", forKey: "aiBackend")
        defaults.set("gpt-4o-mini", forKey: "selectedModel.openai")

        let settings = SettingsService(defaults: defaults, keychain: keychain)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(settings.openAIKey, "sk-existing")
        XCTAssertTrue(settings.hasRequiredAISettings)
        XCTAssertTrue(settings.hasVerifiedAISettings)
        XCTAssertFalse(settings.needsAISetup)
    }

    private func makeSettings() -> (SettingsService, UserDefaults, String) {
        let suite = "HigginsTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (
            SettingsService(
                defaults: defaults,
                keychain: KeychainService(service: suite)
            ),
            defaults,
            suite
        )
    }
}

@MainActor
final class PromptMenuControllerTests: XCTestCase {
    func testMenuMarksAndPositionsTheSelectedPrompt() throws {
        let firstPrompt = SettingsService.Prompt(name: "Improve", content: "Improve")
        let selectedPrompt = SettingsService.Prompt(name: "Formal", content: "Formal")
        let controller = PromptMenuController()

        let presentation = controller.makeMenu(
            prompts: [firstPrompt, selectedPrompt],
            selectedPromptID: selectedPrompt.id
        )

        XCTAssertEqual(presentation.menu.items.map(\.title), ["Prompt:", "", "Improve", "Formal"])
        XCTAssertEqual(presentation.menu.items[2].state, .off)
        XCTAssertEqual(presentation.menu.items[3].state, .on)
        XCTAssertIdentical(presentation.selectedItem, presentation.menu.items[3])
    }

    func testActivatingMenuItemReturnsItsPromptID() {
        let firstPrompt = SettingsService.Prompt(name: "Improve", content: "Improve")
        let secondPrompt = SettingsService.Prompt(name: "Formal", content: "Formal")
        let controller = PromptMenuController()
        let presentation = controller.makeMenu(
            prompts: [firstPrompt, secondPrompt],
            selectedPromptID: firstPrompt.id
        )

        presentation.menu.performActionForItem(at: 3)

        XCTAssertEqual(controller.selectedPromptID, secondPrompt.id)
    }
}
