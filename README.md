# WhisperDB

Instant voice-to-text transcription for macOS and iOS. On macOS, a small Realtime voice window can stream live speech to OpenAI, show verbatim transcript text, and maintain a session to-do list.

## Project Structure

WhisperDB is split into three targets:

- **WhisperDBKit** — shared framework containing the Groq transcription service, OpenRouter AI organize service, transcription model, and config loading
- **WhisperDB** — macOS menubar app
- **WhisperDBiOS** — iOS app

## Features

### macOS

- **Realtime dictation** — streams microphone audio to `gpt-realtime-2`, shows a live verbatim transcript, extracts session to-dos, and copies the final transcript
- **Audio-reactive recording indicator** — the menu bar icon turns red and responds to your voice level while recording
- **Dictation history** — browse, copy, organize, and clear your previous transcriptions
- **Organize with AI** — restructure raw transcriptions into clean markdown using Claude

### iOS

- **Tap-to-record** — large mic button to start and stop recording
- **Audio-reactive animation** — button scales with your voice level
- **Transcription history** — review previous recordings and expand items for copy, organize, and share actions
- **Copy feedback** — visual confirmation when transcription is copied to clipboard

## Keyboard Shortcuts (macOS)

| Shortcut | Action |
|---|---|
| `⌥ Space` | Start Realtime recording or focus the Realtime window |
| Realtime **Stop** button | Stop the current recording |
| `⇧⌥ Space` | Open dictation history window |

## Requirements

- **macOS:** macOS 13+
- **iOS:** iOS 16+
- [Groq API key](https://console.groq.com/) — for Whisper transcription
- [OpenRouter API key](https://openrouter.ai/) — for the Organize feature (uses Claude)
- [OpenAI API key](https://platform.openai.com/api-keys) — for the macOS Realtime voice window

## Setup

1. Clone the repo:
   ```sh
   git clone https://github.com/your-username/whisper-db.git
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
   OPENAI_API_KEY=your_openai_api_key_here
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
2. Press **⌥ Space** to open the Realtime window and start listening
3. Speak naturally — the left pane shows verbatim transcript text and the right pane fills with to-dos
4. Click **Stop** in the Realtime window — the session closes, the transcript is copied, and the window stays open
5. Use **Copy** in the to-do pane to copy the session list
6. Press **⇧⌥ Space** anytime to open a window with your full dictation history

The Realtime session endpoint runs locally inside the macOS app. Browser SDP from the embedded WebView is posted to the app's loopback `/session` endpoint, and the app posts multipart fields named `sdp` and `session` to OpenAI's `/v1/realtime/calls` endpoint with `OPENAI_API_KEY` kept server-side.

### iOS

1. Open the app and tap the microphone button to start recording
2. The button pulses red and scales with your voice level
3. Tap again to stop — the audio is sent to Groq's Whisper API
4. The transcription appears on screen — tap **Copy** to copy it to your clipboard

## Permissions

### macOS
- **Microphone access** — for audio recording

### iOS
- **Microphone access** — for audio recording
