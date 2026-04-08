import Foundation
import SwiftUI

enum RecordingState {
    case idle
    case recording
    case processing
}

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var history: [Transcription] = []
    @Published var lastError: String?

    let recorder = AudioRecorder()
    private var groqService: GroqService?

    let hotKeyManager = HotKeyManager()

    private let maxHistoryItems = 20

    init() {
        do {
            groqService = try GroqService()
        } catch {
            lastError = error.localizedDescription
        }

        hotKeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }

        hotKeyManager.onStopRecording = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.state == .recording else { return }
                self.stopAndTranscribe()
            }
        }

        hotKeyManager.onOpenHistory = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                HistoryWindowController.shared.openWindow(with: self)
            }
        }
    }

    func toggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .processing:
            break // Ignore while processing
        }
    }

    private func startRecording() {
        lastError = nil
        do {
            try recorder.startRecording()
            state = .recording
            hotKeyManager.setRecording(true)
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        hotKeyManager.setRecording(false)

        guard let audioURL = recorder.stopRecording() else {
            lastError = "No audio recorded"
            state = .idle
            return
        }

        state = .processing

        Task {
            defer { recorder.cleanup() }

            guard let service = groqService else {
                lastError = "Groq API not configured"
                state = .idle
                return
            }

            do {
                let text = try await service.transcribe(audioURL: audioURL)
                ClipboardService.copy(text)

                // Brief delay then auto-paste into focused field
                try? await Task.sleep(nanoseconds: 100_000_000)
                ClipboardService.paste()

                let transcription = Transcription(text: text, timestamp: Date())
                history.insert(transcription, at: 0)
                if history.count > maxHistoryItems {
                    history = Array(history.prefix(maxHistoryItems))
                }

                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }

            state = .idle
        }
    }

    func copyFromHistory(_ transcription: Transcription) {
        ClipboardService.copy(transcription.text)
    }

    func clearHistory() {
        history.removeAll()
    }
}
