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

        XCTAssertEqual(presentation.menu.items.map(\.title), ["Improve", "Formal"])
        XCTAssertEqual(presentation.menu.items[0].state, .off)
        XCTAssertEqual(presentation.menu.items[1].state, .on)
        XCTAssertIdentical(presentation.selectedItem, presentation.menu.items[1])
    }

    func testActivatingMenuItemReturnsItsPromptID() {
        let firstPrompt = SettingsService.Prompt(name: "Improve", content: "Improve")
        let secondPrompt = SettingsService.Prompt(name: "Formal", content: "Formal")
        let controller = PromptMenuController()
        let presentation = controller.makeMenu(
            prompts: [firstPrompt, secondPrompt],
            selectedPromptID: firstPrompt.id
        )

        presentation.menu.performActionForItem(at: 1)

        XCTAssertEqual(controller.selectedPromptID, secondPrompt.id)
    }
}
