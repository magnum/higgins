# HigginsAI Agent Notes

## Product Overview
HigginsAI is a macOS menubar app (no Dock icon) that improves selected text with AI. Hotkey `⌃⌥⌘C` opens a prompt picker, copies the selection, sends it to OpenAI or local Ollama, then pastes the result while restoring the previous clipboard.

Origin: evolved from an earlier ButlerAI-inspired codebase into the current HigginsAI architecture (prompt library, Carbon hotkey, Keychain, clearer AI transport). See README for upstream attribution.

## High-Level Architecture
- **UI shell:** SwiftUI `MenuBarExtra` + Settings scene + Logs window
- **State:** `@Observable` `AppState` owns the improve-text flow
- **Prompt UX:** `PromptMenuController` presents an `NSMenu` at the cursor when the hotkey fires
- **Services:** hotkey, accessibility, clipboard, AI clients, settings, logging
- **Persistence:** `SettingsService` uses `UserDefaults` + Keychain (not `@AppStorage`)

## Current Features (evolution)
- Carbon global hotkey (fires without Accessibility)
- Accessibility requested only when simulating ⌘C / ⌘V
- Multi-prompt library with `{selection}` placeholder validation
- Prompt picker at hotkey time (not only in Settings)
- Separate OpenAI base URL (no longer piggybacked on Ollama URL)
- Shared AI transport / error mapping; refusal detection
- OpenAI API key in Keychain (migrates legacy UserDefaults key)
- In-memory logs UI (search, filter, copy, clear)
- Unit tests via `make test` (UI tests removed)

## Key Components
- `Higgins/HigginsApp.swift` — `@main`, `AppState`, `PromptMenuController`, menubar UI
- `Higgins/Services/HotkeyManager.swift` — Carbon `⌃⌥⌘C`
- `Higgins/Services/ClipboardManager.swift` — capture/replace + `PasteboardSnapshot`
- `Higgins/Services/TextImproving.swift` — protocol, prompt rendering, `AITransport`, `AIServiceError`
- `Higgins/Services/OpenAIService.swift` — `OpenAIClient` (filename is legacy)
- `Higgins/Services/OllamaClient.swift` — chat + `/api/tags` model list
- `Higgins/Services/SettingsService.swift` — backend, models, prompts, Keychain key
- `Higgins/Services/KeychainService.swift` — generic-password helpers
- `Higgins/Services/LoggerService.swift` + `Views/LogView.swift`
- `Higgins/Views/SettingsView.swift` — backend / prompts / shortcut
- `Higgins/Models/AIConfiguration.swift` — `AIBackendType`, defaults
- `Higgins/Services/LanguageService.swift` — reserved stub (no language path today)
- `Higgins/AppIntentsSupport.swift` — unused stub

## Data Flow (Runtime)
1. User presses `⌃⌥⌘C`
2. `HotkeyManager` → `AppState.handleHotkey()`
3. Accessibility check (guidance + System Settings if missing)
4. `PromptMenuController` lets the user pick a prompt
5. Frontmost app is reactivated; short delay
6. `ClipboardManager.getSelectedText()` (snapshot → ⌘C)
7. `OpenAIClient` / `OllamaClient` improve via rendered prompt (`{selection}`)
8. `ClipboardManager.replaceSelectedText` (⌘V) then restore prior pasteboard
9. Errors surface via `NSAlert` (config issues can open Settings)

## Settings & Persistence
UserDefaults keys (see `SettingsService.Key`):
- `openaiBaseURL`, `aiBackend`, `ollamaURL`, `selectedModel`
- `prompts.v2` (JSON `[Prompt]`), `selectedPromptID`
- Legacy migration from `promptsData` / `promptNamesData`

Keychain:
- Account `openaiKey` (service = bundle id / `HigginsAI`)

Defaults:
- Backend OpenAI, base URL `https://api.openai.com/v1`
- Ollama `http://localhost:11434`
- Model `gpt-4o-mini`
- One “Default” prompt containing `{selection}`

## Permissions & OS Integration
- Accessibility required for synthetic ⌘C / ⌘V
- Hotkey registration does **not** require Accessibility
- App is `LSUIElement` (menubar-only)
- Deployment target: **macOS 15.2**
- Bundle id: `com.m6i.higgins`

## Build & Test
- Open `Higgins.xcodeproj` in Xcode 16.2+
- Makefile:
  - `make test` — unit tests (`HigginsTests`), optional `xcsift`, prints `tests_run`
  - `make test-build` / `make build` / `make archive` / `make clean`
- Local make targets disable code signing

## Common Entry Points
- App / state: `Higgins/HigginsApp.swift`
- AI: `Higgins/Services/TextImproving.swift`, `OpenAIService.swift`, `OllamaClient.swift`
- Settings UI: `Higgins/Views/SettingsView.swift`
- Clipboard: `Higgins/Services/ClipboardManager.swift`
- Hotkey: `Higgins/Services/HotkeyManager.swift`
- Logs: `Higgins/Views/LogView.swift`

# unit tests
Use XCTest for unit tests.
Implement unit tests to ensure that the code works as intended.
Run the tests before making any changes, add tests to verify the changes, and ensure that the tests pass before considering the session complete.

# xcodebuild
To save context, use `xcsift` when available to format xcodebuild/Swift output.
Always redirect stderr: `… 2>&1 | xcsift -w`
Examples:
```
xcodebuild build 2>&1 | xcsift -w
xcodebuild test 2>&1 | xcsift -w
```
The Makefile falls back to `cat` if `xcsift` is not installed.

# Structure hygiene
Fix all errors, warnings, and failed tests, even if they are not related to the current changes being made.

# grep or search text
Prefer `ast-grep --lang [language] -p '<pattern>'` for structural code search. Use text search only when explicitly needed for plain-text matching.

# tests scope
UI tests have been removed; unit tests are run via `make test`.

# Makefile
- `make test` — run unit tests
- `make test-build` — build-for-testing only
- `make build`
- `make archive`
- `make clean`
