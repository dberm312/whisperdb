import AppKit
import Foundation
import SwiftUI
import WhisperDBKit

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
    let microphoneManager = AudioInputDeviceManager()
    private var groqService: GroqService?

    let hotKeyManager = HotKeyManager()

    let maxRecordingDuration: TimeInterval = 15 * 60

    private let maxHistoryItems = 20
    private let recordingLimitErrorMessage = "Recording stopped at 15 minutes to prevent accidental over-recording."
    private var recordingStartedAt: Date?
    private var recordingLimitTask: Task<Void, Never>?

    var recordingElapsedTime: TimeInterval? {
        guard state == .recording, let recordingStartedAt else { return nil }
        return Date().timeIntervalSince(recordingStartedAt)
    }

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
            NSSound.beep()
        }
    }

    private func startRecording() {
        lastError = nil
        microphoneManager.refreshDevices()

        do {
            try recorder.startRecording(selectedDeviceUID: microphoneManager.recordingDeviceUID)
            recordingStartedAt = Date()
            state = .recording
            hotKeyManager.setRecording(true)
            scheduleRecordingLimitTask()
        } catch {
            recordingStartedAt = nil
            cancelRecordingLimitTask()
            lastError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe(preservedError: String? = nil) {
        hotKeyManager.setRecording(false)
        recordingStartedAt = nil
        cancelRecordingLimitTask()
        if let preservedError {
            lastError = preservedError
        }

        let audioURL = recorder.stopRecording()

        guard let audioURL else {
            lastError = preservedError ?? "No audio recorded"
            state = .idle
            return
        }

        state = .processing

        Task {
            defer {
                recorder.cleanup()
                state = .idle
            }

            guard let service = groqService else {
                lastError = "Groq API not configured"
                return
            }

            do {
                let text = try await service.transcribe(audioURL: audioURL)
                ClipboardService.copy(text)

                let transcription = Transcription(text: text, timestamp: Date())
                history.insert(transcription, at: 0)
                if history.count > maxHistoryItems {
                    history = Array(history.prefix(maxHistoryItems))
                }

                lastError = preservedError
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func copyFromHistory(_ transcription: Transcription) {
        ClipboardService.copy(transcription.text)
    }

    func deleteFromHistory(at index: Int) {
        guard index < history.count else { return }
        history.remove(at: index)
    }

    func clearHistory() {
        history.removeAll()
    }

    private func scheduleRecordingLimitTask() {
        cancelRecordingLimitTask()

        let limitNanoseconds = UInt64(maxRecordingDuration * 1_000_000_000)
        recordingLimitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: limitNanoseconds)
            guard !Task.isCancelled else { return }
            self?.stopBecauseRecordingLimitReached()
        }
    }

    private func cancelRecordingLimitTask() {
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
    }

    private func stopBecauseRecordingLimitReached() {
        guard state == .recording else { return }
        NSSound.beep()
        stopAndTranscribe(preservedError: recordingLimitErrorMessage)
    }

    deinit {
        recordingLimitTask?.cancel()
    }
}
