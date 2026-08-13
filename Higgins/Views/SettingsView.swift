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
            height: settings.aiBackend == .ollama ? 700 : 640
        )
    }
}

private struct AISettingsSection: View {
    @Bindable var settings: SettingsService
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: String?

    var body: some View {
        Section("AI Service") {
            Picker("Backend", selection: $settings.aiBackend) {
                ForEach(AIBackendType.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .pickerStyle(.segmented)

            if settings.aiBackend == .openAI {
                SecureField("API Key", text: $settings.openAIKey)
                TextField("Base URL", text: $settings.openAIBaseURL)
            } else {
                TextField("Server URL", text: $settings.ollamaURL)

                if isLoadingModels {
                    ProgressView("Loading models…")
                } else {
                    Picker("Model", selection: $settings.selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .disabled(availableModels.isEmpty)

                    Button("Refresh Models", systemImage: "arrow.clockwise") {
                        Task { await fetchModels() }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task(id: "\(settings.aiBackend.rawValue):\(settings.ollamaURL)") {
            guard settings.aiBackend == .ollama else { return }
            await fetchModels()
        }
    }

    private func fetchModels() async {
        isLoadingModels = true
        errorMessage = nil
        defer { isLoadingModels = false }

        do {
            availableModels = try await OllamaClient.fetchModels(serverURL: settings.ollamaURL)
            if let firstModel = availableModels.first,
               !availableModels.contains(settings.selectedModel) {
                settings.selectedModel = firstModel
            }
        } catch {
            availableModels = []
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
                Picker("Active Prompt", selection: promptSelection) {
                    ForEach(settings.prompts) { prompt in
                        Text(prompt.name).tag(prompt.id)
                    }
                }

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
