# GenUI Shopping Assistant Demo

A Flutter demo app that showcases the potential of GenUI — a framework where the AI dynamically composes Flutter widget trees at runtime. No pre-coded UI branches required.

The app supports two AI backends, each on its native platform:

| Provider | Platform | SDK |
|----------|----------|-----|
| **Gemini** (Firebase AI Logic) | Chrome / Web | `genui_firebase_ai` |
| **Claude** (Anthropic) | macOS | `genui_dartantic` + `dartantic_ai` |

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure Firebase (Gemini / web)

```bash
# Install FlutterFire CLI if needed
dart pub global activate flutterfire_cli

# Configure — this generates lib/firebase_options.dart
flutterfire configure
```

Then enable **Firebase AI Logic** in the Firebase Console for your project.

### 3. Configure Anthropic (Claude / macOS)

Obtain an API key from [console.anthropic.com](https://console.anthropic.com) and export it in your shell:

```bash
export CLAUDE_SHOPPING_ASSISTANT_KEY="sk-ant-..."
```

The `.vscode/launch.json` configurations pass the key at build time via `--dart-define`.

## Running the app

Use the VS Code launch configurations:

- **Launch Shopping Assistant (macOS)** — runs with Claude on the macOS desktop target.
- **Launch Shopping Assistant (Chrome)** — runs with Gemini in Chrome.

## Why one provider per platform?

- **Anthropic's API** does not support cross-origin browser requests (CORS), so Claude only works on native targets.
- **Firebase AI Logic** requires platform-specific SDK setup. This demo configures only the web target, so Gemini only works in Chrome.

## GenUI version

This demo targets **GenUI v0.7.0** (alpha). Pin your versions and watch the changelog as the API may evolve before the stable release.
