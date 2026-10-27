import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsService
    @State private var isVerifiedWithTest = false
    @State private var isVerificationInProgress = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                if settings.needsAISetup {
                    Text("Please set AI settings")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 2)

            VStack(spacing: 8) {
                AISettingsSection(
                    settings: settings,
                    isVerifiedWithTest: $isVerifiedWithTest,
                    isVerificationInProgress: $isVerificationInProgress
                )
                PromptSettingsSection(settings: settings)
                ShortcutSettingsSection(settings: settings)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Button {
                settings.saveAISettings(verifiedByTest: isVerifiedWithTest)
            } label: {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Text("Created by [Antonio Molinari](https://higgins.m6i.it)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .frame(width: 440, height: windowHeight)
        .onAppear {
            isVerifiedWithTest = settings.hasVerifiedAISettings && settings.hasRequiredAISettings
        }
    }

    private var canSave: Bool {
        settings.hasRequiredAISettings && isVerifiedWithTest && !isVerificationInProgress
    }

    private var windowHeight: CGFloat {
        var height: CGFloat = settings.aiBackend == .ollama ? 620 : 650
        if settings.needsAISetup {
            height += 22
        }
        return height
    }
}

private struct AISettingsSection: View {
    @Bindable var settings: SettingsService
    @Binding var isVerifiedWithTest: Bool
    @Binding var isVerificationInProgress: Bool
    @State private var availableModels: [String] = []
    @State private var modelsBackend: AIBackendType?
    @State private var errorMessage: String?

    var body: some View {
        SettingsGroup("AI Service") {
            FillingPopUpPicker(
                items: AIBackendType.allCases.map { ($0, $0.displayName) },
                selection: $settings.aiBackend
            )

            HStack {
                FillingPopUpPicker(
                    items: modelOptions.map { ($0, $0) },
                    selection: $settings.selectedModel
                )
                .disabled(isVerificationInProgress || modelOptions.isEmpty)
                .help("Model")

                if isVerificationInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh models")
                }
            }

            switch settings.aiBackend {
            case .openAI:
                apiKeyField(text: $settings.openAIKey)
            case .anthropic:
                apiKeyField(text: $settings.anthropicKey)
            case .ollama:
                EmptyView()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: modelSourceID) {
            // Debounce while the user is still typing a key or URL.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await fetchModels()
        }
    }

    /// Horizontal inset of the title inside a pop-up button, so the label
    /// lines up with the values shown in the menus above.
    private static let popUpTitleInset: CGFloat = 10

    private func apiKeyField(text: Binding<String>) -> some View {
        // An HStack instead of LabeledContent, whose label column takes extra width:
        // the label hugs its text and the field fills the rest of the row.
        HStack {
            Text("API Key")
                .padding(.leading, Self.popUpTitleInset)
                .fixedSize()
            SecureField("API Key", text: text)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
        }
    }

    /// Fetched models plus the current selection, so the picker never loses it.
    private var modelOptions: [String] {
        // A list fetched for another backend is stale until the new fetch completes.
        let fetched = modelsBackend == settings.aiBackend ? availableModels : []
        let current = settings.selectedModel
        guard !current.isEmpty, !fetched.contains(current) else {
            return fetched
        }
        return [current] + fetched
    }

    /// Changes whenever the inputs that determine the model list change.
    private var modelSourceID: String {
        switch settings.aiBackend {
        case .openAI:
            "openai:\(settings.openAIKey)"
        case .anthropic:
            "anthropic:\(settings.anthropicKey)"
        case .ollama:
            "ollama"
        }
    }

    private func fetchModels() async {
        let backend = settings.aiBackend
        isVerificationInProgress = true
        isVerifiedWithTest = false
        errorMessage = nil
        defer { isVerificationInProgress = false }

        do {
            let models = switch backend {
            case .openAI:
                try await OpenAIClient.fetchModels(apiKey: settings.openAIKey)
            case .anthropic:
                try await AnthropicClient.fetchModels(apiKey: settings.anthropicKey)
            case .ollama:
                try await OllamaClient.fetchModels()
            }
            // Ignore results that arrive after the user switched backend.
            guard backend == settings.aiBackend else { return }
            availableModels = models
            modelsBackend = backend
            if let firstModel = models.first, !models.contains(settings.selectedModel) {
                settings.selectedModel = firstModel
            }
            isVerifiedWithTest = !models.isEmpty
        } catch {
            guard backend == settings.aiBackend, !Task.isCancelled else { return }
            availableModels = []
            modelsBackend = backend
            isVerifiedWithTest = false
            errorMessage = error.localizedDescription
        }
    }
}

private struct PromptSettingsSection: View {
    @Bindable var settings: SettingsService
    @State private var editor: PromptEditor?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        SettingsGroup("Prompt") {
            HStack {
                FillingPopUpPicker(
                    items: settings.prompts.map { ($0.id, $0.name) },
                    selection: promptSelection
                )

                Button {
                    editor = .rename
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .help("Rename selected prompt")

                Button {
                    editor = .add
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .help("Add prompt")

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .help("Delete selected prompt")
                .disabled(settings.prompts.count == 1)
            }

            // One form row, so no separator is drawn between the editor and its hint.
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $settings.improvementPrompt)
                    .font(.body)
                    .frame(minHeight: 90)
                    .padding(4)
                    .background(.background)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }

                Text("use {selection} as selected text placeholder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editor) { editor in
            PromptNameEditor(
                title: editor == .add ? "New Prompt" : "Rename Prompt",
                initialName: editor == .add ? "" : settings.selectedPromptName,
                existingNames: existingNames(for: editor)
            ) { name in
                switch editor {
                case .add:
                    settings.addPrompt(named: name, content: settings.improvementPrompt)
                case .rename:
                    settings.renameSelectedPrompt(to: name)
                }
                self.editor = nil
            }
        }
        .alert("Delete selected prompt?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                settings.removeSelectedPrompt()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var promptSelection: Binding<SettingsService.Prompt.ID> {
        Binding(
            get: { settings.selectedPromptID },
            set: settings.selectPrompt(id:)
        )
    }

    private func existingNames(for editor: PromptEditor) -> [String] {
        settings.prompts.compactMap { prompt in
            editor == .rename && prompt.id == settings.selectedPromptID ? nil : prompt.name
        }
    }

    private enum PromptEditor: String, Identifiable {
        case add
        case rename

        var id: Self { self }
    }
}

private struct PromptNameEditor: View {
    let title: LocalizedStringResource
    let existingNames: [String]
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(
        title: LocalizedStringResource,
        initialName: String,
        existingNames: [String],
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.existingNames = existingNames
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("Prompt name", text: $name)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Save") {
                    onSave(trimmedName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: LocalizedStringResource? {
        if trimmedName.isEmpty {
            "Name cannot be empty."
        } else if existingNames.contains(where: {
            $0.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            "A prompt with this name already exists."
        } else {
            nil
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: .rect(cornerRadius: 8))
        }
    }
}

/// A pop-up menu that fills the available width.
/// SwiftUI's menu `Picker` keeps the pop-up button at its intrinsic width on macOS,
/// so `.frame(maxWidth: .infinity)` only centers it instead of stretching it.
private struct FillingPopUpPicker<ID: Hashable>: NSViewRepresentable {
    let items: [(id: ID, title: String)]
    @Binding var selection: ID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = { index in
            guard items.indices.contains(index) else { return }
            selection = items[index].id
        }

        let titles = items.map(\.title)
        if button.itemTitles != titles {
            // NSPopUpButton merges duplicate titles, so add items through the menu.
            button.removeAllItems()
            for title in titles {
                button.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
            }
        }

        if let index = items.firstIndex(where: { $0.id == selection }) {
            button.selectItem(at: index)
        } else {
            button.select(nil)
        }
        button.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let intrinsicSize = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsicSize.width, height: intrinsicSize.height)
    }

    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void = { _ in }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            onSelect(sender.indexOfSelectedItem)
        }
    }
}

private struct ShortcutSettingsSection: View {
    @Bindable var settings: SettingsService

    var body: some View {
        SettingsGroup("Keyboard Shortcut") {
            // An HStack instead of LabeledContent: the form aligns a LabeledContent
            // label to the first text baseline, not to the center of the large box.
            HStack(alignment: .center) {
                Text("Click to change, enter to confirm")
                Spacer()
                ShortcutRecorder(settings: settings)
            }
        }
    }
}

/// Shows the current shortcut; clicking it captures the next key combination.
/// Every key is accepted except Return/Enter, which saves and ends recording.
private struct ShortcutRecorder: View {
    @Bindable var settings: SettingsService
    @State private var pendingShortcut: HotkeyShortcut?
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var eventMonitor: Any?

    var body: some View {
        Button {
            if settings.isRecordingHotkey {
                stopRecording(saving: false)
            } else {
                startRecording()
            }
        } label: {
            Text(displayText)
                .font(.title2.monospaced().weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minWidth: 120)
                .background(
                    settings.isRecordingHotkey ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(settings.isRecordingHotkey ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(settings.isRecordingHotkey ? "Press the new shortcut, then Return to save. Click to cancel." : "Click to change the shortcut")
        .onDisappear {
            stopRecording(saving: false)
        }
    }

    private var displayText: String {
        guard settings.isRecordingHotkey else {
            return settings.hotkeyShortcut.displayString
        }
        if let pendingShortcut {
            return pendingShortcut.displayString
        }
        let modifiers = HotkeyShortcut.symbols(for: liveModifiers)
        return modifiers.isEmpty ? "Press keys…" : modifiers
    }

    private func startRecording() {
        pendingShortcut = nil
        liveModifiers = []
        settings.isRecordingHotkey = true
        // A local monitor sees keys before menus and controls, so it can swallow
        // combinations like ⌘W or ⌘Q while recording.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(HotkeyShortcut.supportedModifiers)
        switch event.type {
        case .flagsChanged:
            liveModifiers = modifiers
        case .keyDown:
            if let shortcut = HotkeyShortcut(event: event) {
                pendingShortcut = shortcut
            } else {
                // Return/Enter confirms the captured combination.
                stopRecording(saving: true)
            }
        default:
            break
        }
    }

    private func stopRecording(saving: Bool) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        if saving, let pendingShortcut {
            settings.hotkeyShortcut = pendingShortcut
        }
        pendingShortcut = nil
        liveModifiers = []
        if settings.isRecordingHotkey {
            settings.isRecordingHotkey = false
        }
    }
}

#Preview {
    SettingsView(settings: SettingsService())
}
