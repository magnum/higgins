import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsService

    var body: some View {
        Form {
            AISettingsSection(settings: settings)
            PromptSettingsSection(settings: settings)
            ShortcutSettingsSection()
        }
        .formStyle(.grouped)
        .frame(
            width: 440,
            height: settings.aiBackend == .openAI ? 700 : 670
        )
    }
}

private struct AISettingsSection: View {
    @Bindable var settings: SettingsService
    @State private var availableModels: [String] = []
    @State private var modelsBackend: AIBackendType?
    @State private var isLoadingModels = false
    @State private var errorMessage: String?

    var body: some View {
        Section("AI Service") {
            FillingPopUpPicker(
                items: AIBackendType.allCases.map { ($0, $0.displayName) },
                selection: $settings.aiBackend
            )

            switch settings.aiBackend {
            case .openAI:
                SecureField("API Key", text: $settings.openAIKey)
                TextField("Base URL", text: $settings.openAIBaseURL)
            case .anthropic:
                SecureField("API Key", text: $settings.anthropicKey)
            case .ollama:
                TextField("Server URL", text: $settings.ollamaURL)
            }

            HStack {
                FillingPopUpPicker(
                    items: modelOptions.map { ($0, $0) },
                    selection: $settings.selectedModel
                )
                .disabled(isLoadingModels || modelOptions.isEmpty)
                .help("Model")

                if isLoadingModels {
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
            "openai:\(settings.openAIBaseURL):\(settings.openAIKey)"
        case .anthropic:
            "anthropic:\(settings.anthropicKey)"
        case .ollama:
            "ollama:\(settings.ollamaURL)"
        }
    }

    private func fetchModels() async {
        let backend = settings.aiBackend
        isLoadingModels = true
        errorMessage = nil
        defer { isLoadingModels = false }

        do {
            let models = switch backend {
            case .openAI:
                try await OpenAIClient.fetchModels(
                    apiKey: settings.openAIKey,
                    serverURL: settings.openAIBaseURL
                )
            case .anthropic:
                try await AnthropicClient.fetchModels(apiKey: settings.anthropicKey)
            case .ollama:
                try await OllamaClient.fetchModels(serverURL: settings.ollamaURL)
            }
            // Ignore results that arrive after the user switched backend.
            guard backend == settings.aiBackend else { return }
            availableModels = models
            modelsBackend = backend
            if let firstModel = models.first, !models.contains(settings.selectedModel) {
                settings.selectedModel = firstModel
            }
        } catch {
            guard backend == settings.aiBackend, !Task.isCancelled else { return }
            availableModels = []
            modelsBackend = backend
            errorMessage = error.localizedDescription
        }
    }
}

private struct PromptSettingsSection: View {
    @Bindable var settings: SettingsService
    @State private var editor: PromptEditor?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Section("Prompt") {
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

            TextEditor(text: $settings.improvementPrompt)
                .font(.body)
                .frame(minHeight: 180)
                .padding(4)
                .background(.background)
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                }

            Text("use {selection} as selected text placeholder")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    var body: some View {
        Section("Keyboard Shortcut") {
            LabeledContent("Improve selected text") {
                Text("⌃⌥⌘C")
                    .monospaced()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
            }
        }
    }
}

#Preview {
    SettingsView(settings: SettingsService())
}
