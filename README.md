# WhisperDB

Instant voice-to-text transcription for macOS and iOS. Speak, and your words are transcribed using Whisper (via Groq) and ready to use.

## Project Structure

WhisperDB is split into three targets:

- **WhisperDBKit** — shared framework containing the Groq transcription service, OpenRouter AI organize service, transcription model, and config loading
- **WhisperDB** — macOS menubar app
- **WhisperDBiOS** — iOS app

## Features

### macOS

- **Instant dictation** — transcribes speech using Whisper (via Groq) and copies the result to your clipboard
- **Auto-paste** — automatically pastes the transcription into the focused text field
- **Audio-reactive recording indicator** — pulsing red circle in the menu bar shows when you're recording
- **Dictation history** — browse and search all your previous transcriptions
- **Organize with AI** — restructure raw transcriptions into clean markdown using Claude
- **Media control** — automatically pauses music/podcasts while recording

### iOS

- **Tap-to-record** — large mic button to start and stop recording
- **Audio-reactive animation** — button scales with your voice level
- **Live transcription display** — selectable text you can copy with one tap
- **Copy feedback** — visual confirmation when transcription is copied to clipboard

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
|---|---|
| `⌥ Space` | Start recording |
| `⌥` (Option alone) | Stop recording |
| `⇧⌥ Space` | Open dictation history window |

## Requirements

- **macOS:** macOS 13+
- **iOS:** iOS 16+
- [Groq API key](https://console.groq.com/) — for Whisper transcription
- [OpenRouter API key](https://openrouter.ai/) — for the Organize feature (uses Claude)

## Setup

1. Clone the repo:
   ```sh
   git clone https://github.com/dberm312/whisperdb.git
   cd whisper-db
   ```

2. **macOS** — Create a `.env` file from the example:
   ```sh
   cp .env.example .env
   ```
   Add your API keys to `.env`:
   ```
   GROQ_API_KEY=your_groq_api_key_here
   OPENROUTER_API_KEY=your_openrouter_api_key_here
   ```

3. **iOS** — Create a `Config.plist` at `WhisperDBiOS/WhisperDBiOS/Config.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>GROQ_API_KEY</key>
       <string>your_groq_api_key_here</string>
       <key>OPENROUTER_API_KEY</key>
       <string>your_openrouter_api_key_here</string>
   </dict>
   </plist>
   ```

## Build & Run

### macOS

```sh
swift build
swift run WhisperDB
```

Or open in Xcode:
```sh
open Package.swift
```

Then build and run with `⌘R`.

### iOS

Open the Xcode project:
```sh
open WhisperDBiOS/WhisperDBiOS.xcodeproj
```

Select an iOS simulator or connected device, then build and run with `⌘R`.

## How It Works

### macOS

1. WhisperDB lives in your menu bar with a captions icon
2. Press **⌥ Space** to start recording — the icon turns into a pulsing red circle
3. Speak your dictation
4. Press **⌥** (Option key) to stop — the audio is sent to Groq's Whisper API
5. The transcription is copied to your clipboard and auto-pasted into the focused field
6. Press **⇧⌥ Space** anytime to open a window with your full dictation history

### iOS

1. Open the app and tap the microphone button to start recording
2. The button pulses red and scales with your voice level
3. Tap again to stop — the audio is sent to Groq's Whisper API
4. The transcription appears on screen — tap **Copy** to copy it to your clipboard

## Permissions

### macOS
- **Microphone access** — for audio recording
- **Accessibility** — for auto-paste (simulates ⌘V)

### iOS
- **Microphone access** — for audio recording
