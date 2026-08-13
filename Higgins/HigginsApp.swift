import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    private var hotkeyManager: HotkeyManager?
    private let clipboardManager = ClipboardManager()
    private let promptMenuController = PromptMenuController()

    let settings = SettingsService()
    private(set) var isProcessing = false
    private(set) var lastError: String?
    var openSettings: (() -> Void)?

    init() {
        log("Starting HigginsAI")
        guard !RuntimeEnvironment.isRunningTests else {
            log("Skipping global hotkey setup during tests")
            return
        }
        setupHotkey()
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.handleHotkey()
        }

        DispatchQueue.main.async { [weak self] in
            self?.requestAccessibilityPermission(showGuidance: true)
        }
    }

    private func handleHotkey() {
        guard !isProcessing else { return }
        guard requestAccessibilityPermission(showGuidance: true) else { return }
        let sourceApplication = NSWorkspace.shared.frontmostApplication

        guard let promptID = promptMenuController.present(
            prompts: settings.prompts,
            selectedPromptID: settings.selectedPromptID,
            at: NSEvent.mouseLocation
        ) else {
            return
        }

        settings.selectPrompt(id: promptID)
        sourceApplication?.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await improveSelectedText()
        }
    }

    private func improveSelectedText() async {
        isProcessing = true
        var shouldRestoreClipboard = false
        defer {
            if shouldRestoreClipboard {
                clipboardManager.restoreClipboard()
            }
            isProcessing = false
        }

        do {
            let selectedText = try await clipboardManager.getSelectedText()
            shouldRestoreClipboard = true
            log("Captured selected text (\(selectedText.count) characters)")

            let improvedText = try await makeTextImprover().improveText(selectedText)
            try await clipboardManager.replaceSelectedText(with: improvedText)
            shouldRestoreClipboard = false

            lastError = nil
            log("Text replaced successfully")
        } catch let error as ClipboardManager.ClipboardError {
            presentError(
                title: "No Text Selected",
                message: error.localizedDescription
            )
        } catch let error as AIServiceError {
            presentError(
                title: "\(settings.aiBackend.displayName) Error",
                message: error.localizedDescription,
                offersSettings: error.isConfigurationError
            )
        } catch {
            presentError(
                title: "Unexpected Error",
                message: error.localizedDescription
            )
        }
    }

    private func makeTextImprover() -> any TextImproving {
        switch settings.aiBackend {
        case .openAI:
            OpenAIClient(
                apiKey: settings.openAIKey,
                prompt: settings.improvementPrompt,
                model: settings.selectedModel,
                serverURL: settings.openAIBaseURL
            )
        case .ollama:
            OllamaClient(
                prompt: settings.improvementPrompt,
                model: settings.selectedModel,
                serverURL: settings.ollamaURL
            )
        }
    }

    @discardableResult
    private func requestAccessibilityPermission(showGuidance: Bool) -> Bool {
        guard !AXIsProcessTrusted() else { return true }

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
        guard showGuidance else { return false }

        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "HigginsAI needs Accessibility access to copy and replace selected text. Enable it in System Settings → Privacy & Security → Accessibility, then use ⌃⌥⌘C again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func presentError(title: String, message: String, offersSettings: Bool = false) {
        lastError = message
        log(message, type: .error)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if offersSettings {
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.addButton(withTitle: "OK")
        }

        NSApp.activate(ignoringOtherApps: true)
        if offersSettings, alert.runModal() == .alertFirstButtonReturn {
            if let openSettings {
                openSettings()
            } else {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } else if !offersSettings {
            alert.runModal()
        }
    }
}

@MainActor
final class PromptMenuController: NSObject {
    private(set) var selectedPromptID: SettingsService.Prompt.ID?

    func present(
        prompts: [SettingsService.Prompt],
        selectedPromptID: SettingsService.Prompt.ID,
        at screenLocation: NSPoint
    ) -> SettingsService.Prompt.ID? {
        let presentation = makeMenu(
            prompts: prompts,
            selectedPromptID: selectedPromptID
        )
        self.selectedPromptID = nil

        // Offset the popup below the mouse so the cursor lands on the disabled header
        let headerOffset: CGFloat = 28
        let adjustedPoint = NSPoint(x: screenLocation.x, y: screenLocation.y - headerOffset)

        presentation.menu.popUp(
            positioning: presentation.selectedItem,
            at: adjustedPoint,
            in: nil
        )
        return self.selectedPromptID
    }

    func makeMenu(
        prompts: [SettingsService.Prompt],
        selectedPromptID: SettingsService.Prompt.ID
    ) -> (menu: NSMenu, selectedItem: NSMenuItem?) {
        let menu = NSMenu(title: "Prompts")
        menu.autoenablesItems = false

        // Add a non-selectable header to prevent initial mouse hover from stealing focus
        let headerItem = NSMenuItem()
        headerItem.title = "Prompt:"
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        var selectedItem: NSMenuItem?

        for prompt in prompts {
            let item = NSMenuItem(
                title: prompt.name,
                action: #selector(selectPrompt(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = prompt.id.uuidString

            if prompt.id == selectedPromptID {
                item.state = .on
                selectedItem = item
            }
            menu.addItem(item)
        }

        return (menu, selectedItem)
    }

    @objc func selectPrompt(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String else { return }
        selectedPromptID = UUID(uuidString: rawID)
    }
}

private extension AIServiceError {
    var isConfigurationError: Bool {
        switch self {
        case .missingAPIKey, .invalidURL:
            true
        default:
            false
        }
    }
}

@main
struct HigginsApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: appState)
        } label: {
            ProcessingIcon(isProcessing: appState.isProcessing)
        }

        Settings {
            SettingsView(settings: appState.settings)
        }

        Window("HigginsAI Logs", id: "logs") {
            LogView()
        }
        .defaultSize(width: 800, height: 600)
    }
}

struct MenuContentView: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Label {
                Text("HigginsAI")
                    .font(.headline)
            } icon: {
                ProcessingIcon(isProcessing: appState.isProcessing)
                    .frame(width: 18, height: 18)
            }
            .padding(.vertical, 8)

            Divider()

            if let error = appState.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .lineLimit(3)
                    .padding(8)
                Divider()
            }

            Button("Show Logs") {
                openWindow(id: "logs")
            }
            .keyboardShortcut("l")

            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit HigginsAI") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .fixedSize()
        .onAppear {
            appState.openSettings = { openSettings() }
        }
    }
}

private struct ProcessingIcon: View {
    let isProcessing: Bool

    var body: some View {
        Image(systemName: isProcessing ? "clock.arrow.circlepath" : "wand.and.stars")
            .imageScale(.medium)
            .rotationEffect(.degrees(isProcessing ? 360 : 0))
            .animation(
                isProcessing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                value: isProcessing
            )
    }
}
