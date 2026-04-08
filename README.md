# WhisperDB

A macOS menubar app for instant voice-to-text transcription. Press a keyboard shortcut, speak, and your words are transcribed and pasted into whatever you're typing in.

## Features

- **Instant dictation** — transcribes speech using Whisper (via Groq) and copies the result to your clipboard
- **Auto-paste** — automatically pastes the transcription into the focused text field
- **Audio-reactive recording indicator** — pulsing red circle in the menu bar shows when you're recording
- **Dictation history** — browse and search all your previous transcriptions
- **Organize with AI** — restructure raw transcriptions into clean markdown using Claude

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌥ Space` | Start recording |
| `⌥` (Option alone) | Stop recording |
| `⇧⌥ Space` | Open dictation history window |

## Requirements

- macOS 13+
- [Groq API key](https://console.groq.com/) — for Whisper transcription
- [OpenRouter API key](https://openrouter.ai/) — for the Organize feature (uses Claude)

## Setup

1. Clone the repo:
   ```sh
   git clone https://github.com/your-username/whisper-db.git
   cd whisper-db
   ```

2. Create a `.env` file from the example:
   ```sh
   cp .env.example .env
   ```

3. Add your API keys to `.env`:
   ```
   GROQ_API_KEY=your_groq_api_key_here
   OPENROUTER_API_KEY=your_openrouter_api_key_here
   ```

## Build & Run

```sh
swift build
swift run WhisperDB
```

Or open the project in Xcode:
```sh
open Package.swift
```

Then build and run with `⌘R`.

## How It Works

1. WhisperDB lives in your menu bar with a captions icon
2. Press **⌥ Space** to start recording — the icon turns into a pulsing red circle
3. Speak your dictation
4. Press **⌥** (Option key) to stop — the audio is sent to Groq's Whisper API
5. The transcription is copied to your clipboard and auto-pasted into the focused field
6. Press **⇧⌥ Space** anytime to open a window with your full dictation history

## Permissions

The app requires:
- **Microphone access** — for audio recording
- **Accessibility** — for auto-paste (simulates ⌘V)
