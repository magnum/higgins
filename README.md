# Higgins

> Inspired by [ButlerAI](https://github.com/gscalzo/ButlerAI) by Giordano Scalzo — this project started from that repository and evolved into Higgins.

Higgins is a macOS menubar app that improves selected text with AI. Select text in any app, press a shortcut, pick a prompt, and the improved version is pasted back in place.

The latest signed build is [Higgins 0.2](https://github.com/magnum/higgins/releases/tag/v0.2).

## Features

- **Global shortcut** — default `⌃⌥⌘C`, configurable in Settings; works system-wide from the menubar (no Dock icon)
- **Prompt picker on demand** — choose which prompt to apply when the hotkey fires
- **OpenAI, Claude (Anthropic), or Ollama** — cloud APIs or fully local models
- **First-run AI setup** — on launch (and on the shortcut) Settings opens until provider, model, and API key are saved and verified with a test call
- **Persistent settings** — provider, model, prompts, and shortcut are stored on the Mac and stay in sync when you change them
- **Custom prompts** — named prompt library; each prompt must include `{selection}`
- **Clipboard-safe** — previous pasteboard contents are restored after replace
- **Secure API key storage** — OpenAI and Anthropic keys kept in the macOS Keychain
- **Accessibility-aware** — Carbon hotkey registers without Accessibility; permission is requested only when simulating ⌘C / ⌘V
- **In-app logs** — searchable log window for debugging requests and errors

## Requirements

- macOS 15.2 or later
- Xcode 16.2+ (for building from source)
- One of:
  - an [OpenAI](https://platform.openai.com/) API key
  - an [Anthropic](https://console.anthropic.com/) API key (Claude)
  - [Ollama](https://ollama.ai/download) running locally

## Setup

1. Launch Higgins (wand icon in the menubar)
2. If AI settings are not configured yet, **Settings** opens automatically with **Please set AI settings**
3. Choose a backend:
   - **OpenAI** — paste your API key (default model `gpt-4o-mini`)
   - **Anthropic** — paste your API key (Claude; default model `claude-opus-5-5`)
   - **Ollama** — local server at `http://localhost:11434`; refresh the model list and pick a model
4. Wait for the test call (model list) to succeed, then click **Save**
5. Optionally change the keyboard shortcut
6. Grant **Accessibility** when prompted (needed to read/replace the selection)

Until provider, model, and key are saved and verified, the shortcut opens Settings instead of improving text.

## Usage

1. Select text in any application
2. Press the shortcut (default `⌃⌥⌘C`)
3. Pick a prompt from the popup menu
4. Higgins copies the selection, sends it to the AI backend, and pastes the result

### Prompt format

Prompts must include the `{selection}` placeholder. Example:

```text
Improve the following text. Keep meaning and language. Return only the result.

Text:
{selection}
```

## Privacy

- With **Ollama**, text stays on your machine
- With **OpenAI** or **Anthropic**, text is sent to that provider’s API
- Nothing is stored permanently by the app beyond your settings and Keychain secrets
- Clipboard content is snapshotted and restored after each run

## What’s new in 0.2

- Claude / Anthropic as a first-class backend
- First-run setup with API-key verification before Save
- Shortcut and launch always open Settings until AI settings are complete
- Settings persist locally and update as you change them
- Configurable global hotkey
- Compact Settings layout (tighter sections, shorter prompt editor, full-width Save)

## Development

```bash
make build       # Build the app
make test        # Run unit tests
make test-build  # Compile tests only
make archive     # Create an archive
make clean       # Remove DerivedData / build artifacts
```

Open `Higgins.xcodeproj` in Xcode for interactive work. Agent-oriented project notes live in [`AGENTS.md`](AGENTS.md).

### Release tags

Pushing a `v*` tag runs the GitHub Action that builds, signs, notarizes, and publishes a DMG (requires the repo signing secrets).

## License

MIT — see [LICENSE](LICENSE).
