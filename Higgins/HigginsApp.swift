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
        log("Starting Higgins")
        guard !RuntimeEnvironment.isRunningTests else {
            log("Skipping global hotkey setup during tests")
            return
        }
        setupHotkey()
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(shortcut: settings.hotkeyShortcut) { [weak self] in
            self?.handleHotkey()
        }
        settings.onHotkeyConfigurationChange = { [weak self] in
            self?.updateHotkey()
        }

        DispatchQueue.main.async { [weak self] in
            self?.requestAccessibilityPermission(showGuidance: true)
        }

        if settings.needsAISetup {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.presentSettings()
            }
        }
    }

    func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let openSettings {
            openSettings()
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        bringWindowToFront { $0.localizedCaseInsensitiveContains("settings") }
    }

    /// Menu-bar apps aren't active by default, so windows would otherwise
    /// open behind the frontmost application. Wait for SwiftUI to create
    /// the window, then bring it front.
    func bringWindowToFront(matching matchesIdentifier: @escaping (String) -> Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            NSApp.activate()
            guard let window = NSApp.windows.first(where: { window in
                window.identifier.map { matchesIdentifier($0.rawValue) } ?? false
            }) else {
                let identifiers = NSApp.windows.compactMap(\.identifier?.rawValue)
                log("Window to bring to front not found among: \(identifiers)", type: .error)
                return
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func updateHotkey() {
        guard let hotkeyManager else { return }
        if settings.isRecordingHotkey {
            hotkeyManager.suspend()
        } else {
            hotkeyManager.update(shortcut: settings.hotkeyShortcut)
        }
    }

    private func handleHotkey() {
        guard !isProcessing else { return }
        if settings.needsAISetup {
            presentSettings()
            return
        }
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
                model: settings.selectedModel
            )
        case .anthropic:
            AnthropicClient(
                apiKey: settings.anthropicKey,
                prompt: settings.improvementPrompt,
                model: settings.selectedModel
            )
        case .ollama:
            OllamaClient(
                prompt: settings.improvementPrompt,
                model: settings.selectedModel
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
        alert.informativeText = "Higgins needs Accessibility access to copy and replace selected text. Enable it in System Settings → Privacy & Security → Accessibility, then use \(settings.hotkeyShortcut.displayString) again."
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

        Window("Higgins Logs", id: "logs") {
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
                Text("Higgins")
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
                showLogs()
            }
            .keyboardShortcut("l")

            Button("Settings…") {
                showSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Higgins") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .fixedSize()
        .onAppear {
            appState.openSettings = { showSettings() }
        }
    }

    /// Opens the Settings window and brings it to the front.
    private func showSettings() {
        openSettings()
        appState.bringWindowToFront { $0.localizedCaseInsensitiveContains("settings") }
    }

    /// Opens the Logs window and brings it to the front.
    private func showLogs() {
        openWindow(id: "logs")
        appState.bringWindowToFront { $0.hasPrefix("logs") }
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
