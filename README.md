# HigginsAI

> Inspired by [ButlerAI](https://github.com/gscalzo/ButlerAI) by Giordano Scalzo — this project started from that repository and evolved into HigginsAI.

HigginsAI is a macOS menubar app that improves selected text with AI. Select text in any app, press a shortcut, pick a prompt, and the improved version is pasted back in place.

## Features

- **Global shortcut** — `⌃⌥⌘C` works system-wide from the menubar (no Dock icon)
- **Prompt picker on demand** — choose which prompt to apply when the hotkey fires
- **OpenAI or Ollama** — cloud API or fully local models
- **Custom prompts** — named prompt library; each prompt must include `{selection}`
- **Clipboard-safe** — previous pasteboard contents are restored after replace
- **Secure API key storage** — OpenAI key kept in the macOS Keychain
- **Accessibility-aware** — Carbon hotkey registers without Accessibility; permission is requested only when simulating ⌘C / ⌘V
- **In-app logs** — searchable log window for debugging requests and errors

## Requirements

- macOS 15.2 or later
- Xcode 16.2+ (for building from source)
- Either:
  - an OpenAI API key, or
  - [Ollama](https://ollama.ai/download) running locally

## Setup

1. Launch HigginsAI (wand icon in the menubar)
2. Open **Settings…**
3. Choose a backend:
   - **OpenAI** — paste your API key (optional custom base URL; default model `gpt-4o-mini`)
   - **Ollama** — set the server URL (default `http://localhost:11434`) and refresh the model list
4. Grant **Accessibility** when prompted (needed to read/replace the selection)

## Usage

1. Select text in any application
2. Press `⌃⌥⌘C`
3. Pick a prompt from the popup menu
4. HigginsAI copies the selection, sends it to the AI backend, and pastes the result

### Prompt format

Prompts must include the `{selection}` placeholder. Example:

```text
Improve the following text. Keep meaning and language. Return only the result.

Text:
{selection}
```

## Privacy

- With **Ollama**, text stays on your machine
- With **OpenAI**, text is sent to the configured API endpoint
- Nothing is stored permanently by the app beyond your settings and Keychain secrets
- Clipboard content is snapshotted and restored after each run

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
