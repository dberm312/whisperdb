import AppKit
import Foundation
import ParakeetKit
import SwiftUI
import WhisperDBKit

enum RecordingState {
    case idle
    case recording
    case processing
    /// Recording has stopped but the panel stays open showing the transcript +
    /// summary for review. A second Option tap dismisses it.
    case reviewing
}

/// Lifecycle of the live summary so the UI can show the right indicator.
enum SummaryStatus {
    case idle      // nothing pending
    case waiting   // new speech arrived; waiting for a pause before summarizing
    case loading   // a summarization API call is in flight
    case ready     // summary is up to date
}

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var history: [Transcription] = []
    @Published var lastError: String?

    /// Finalized transcript so far (segments the recognizer has committed).
    @Published var liveText: String = ""
    /// Current interim hypothesis for the segment being spoken (may change).
    @Published var partialText: String = ""

    /// Organized summary of the finalized transcript, refreshed after each speech pause.
    /// Holds the text for the currently selected `summaryLevel`.
    @Published var summaryText: String = ""
    /// Current state of the summary pipeline (waiting for a pause vs. loading).
    @Published var summaryStatus: SummaryStatus = .idle

    /// How aggressively to reshape the live summary. Persisted across launches.
    @Published var summaryLevel: SummaryLevel {
        didSet {
            guard oldValue != summaryLevel else { return }
            UserDefaults.standard.set(summaryLevel.rawValue, forKey: Self.summaryLevelKey)
            switchSummaryLevel(from: oldValue)
        }
    }
    private static let summaryLevelKey = "liveSummaryLevel"

    /// Last finished summary per level for the current transcript, so switching back to
    /// a previously-viewed level shows instantly (then refreshes if the transcript moved on).
    private var summaryCache: [SummaryLevel: String] = [:]

    let recorder = AudioRecorder()
    let microphoneManager = AudioInputDeviceManager()
    private var parakeetService: ParakeetStreamingService?
    private var summaryService: NvidiaSummaryService?

    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var streamingTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var summaryDebounceTask: Task<Void, Never>?
    /// How long speech must be quiet (no new finalized segments) before we summarize.
    private let summaryPauseInterval: TimeInterval = 1.5

    let hotKeyManager = HotKeyManager()

    let maxRecordingDuration: TimeInterval = 15 * 60

    private let minRecordingDuration: TimeInterval = 2.5
    private let silenceThreshold: Float = 0.01
    private let maxHistoryItems = 20
    private let recordingLimitErrorMessage = "Recording stopped at 15 minutes to prevent accidental over-recording."
    private var recordingStartedAt: Date?
    private var recordingLimitTask: Task<Void, Never>?

    var recordingElapsedTime: TimeInterval? {
        guard state == .recording, let recordingStartedAt else { return nil }
        return Date().timeIntervalSince(recordingStartedAt)
    }

    /// The full transcript currently displayed (committed + interim).
    var displayedTranscript: String {
        if partialText.isEmpty { return liveText }
        if liveText.isEmpty { return partialText }
        return liveText + " " + partialText
    }

    init() {
        let savedLevel = UserDefaults.standard.string(forKey: Self.summaryLevelKey)
            .flatMap(SummaryLevel.init(rawValue:))
        summaryLevel = savedLevel ?? .organized

        do {
            parakeetService = try ParakeetStreamingService()
        } catch {
            lastError = error.localizedDescription
        }

        // Optional — transcription still works without it; the summary section just
        // stays empty if the NVIDIA key is missing/invalid.
        summaryService = try? NvidiaSummaryService()

        hotKeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }

        // A clean Option-key tap means "stop" while recording, or "dismiss" while
        // reviewing the stopped result.
        hotKeyManager.onOptionTap = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                switch self.state {
                case .recording: self.finishRecording()
                case .reviewing: self.dismissReview()
                case .idle, .processing: break
                }
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
            finishRecording()
        case .reviewing:
            // Dismiss the review panel and immediately begin a fresh recording.
            dismissReview()
            startRecording()
        case .processing:
            NSSound.beep()
        }
    }

    private func startRecording() {
        lastError = nil
        liveText = ""
        partialText = ""
        summaryText = ""
        summaryCache.removeAll()
        summaryStatus = .idle
        microphoneManager.refreshDevices()

        guard let service = parakeetService else {
            lastError = "NVIDIA Parakeet not configured"
            return
        }

        let (audioStream, continuation) = AsyncStream<Data>.makeStream()
        audioContinuation = continuation

        do {
            try recorder.startStreaming(selectedDeviceUID: microphoneManager.recordingDeviceUID) { [continuation] data in
                continuation.yield(data)
            }
        } catch {
            continuation.finish()
            audioContinuation = nil
            recordingStartedAt = nil
            cancelRecordingLimitTask()
            lastError = "Failed to start recording: \(error.localizedDescription)"
            return
        }

        recordingStartedAt = Date()
        state = .recording
        hotKeyManager.setListening(true)
        scheduleRecordingLimitTask()
        LiveTranscriptionWindowController.shared.resetAutoFit()
        LiveTranscriptionWindowController.shared.show(with: self)

        streamingTask = Task { [weak self] in
            do {
                for try await result in service.transcribe(audio: audioStream) {
                    guard let self else { return }
                    if result.isFinal {
                        self.liveText += (self.liveText.isEmpty ? "" : " ") + result.text
                        self.partialText = ""
                        self.scheduleSummaryAfterPause()
                    } else {
                        self.partialText = result.text
                    }
                }
            } catch is CancellationError {
                // Stream cancelled on stop — not an error.
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    /// Stops the live stream and waits for the final transcript. If anything was
    /// captured it commits the transcript and enters `.reviewing` (panel stays open
    /// until a second Option tap); otherwise it dismisses immediately.
    private func finishRecording(preservedError: String? = nil) {
        guard state == .recording else { return }

        let recordingDuration: TimeInterval =
            if let recordingStartedAt {
                Date().timeIntervalSince(recordingStartedAt)
            } else {
                0
            }
        let peakLevel = recorder.getPeakAudioLevel()

        recordingStartedAt = nil
        cancelRecordingLimitTask()
        if let preservedError {
            lastError = preservedError
        }

        // Stop the microphone tap, then close the audio stream so the recognizer
        // emits its final result and the streaming task completes.
        _ = recorder.stopRecording()
        audioContinuation?.finish()
        audioContinuation = nil

        state = .processing

        Task { [weak self] in
            guard let self else { return }
            await self.streamingTask?.value
            self.streamingTask = nil

            let finalText = self.displayedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

            if recordingDuration < self.minRecordingDuration && preservedError == nil {
                self.dismissReview()
                return
            }
            if peakLevel < self.silenceThreshold && preservedError == nil {
                self.lastError = "Nothing was captured — no sound detected"
                self.dismissReview()
                return
            }
            guard !finalText.isEmpty else {
                if preservedError == nil {
                    self.lastError = "No speech detected"
                }
                self.dismissReview()
                return
            }

            ClipboardService.copy(finalText)

            let transcription = Transcription(text: finalText, timestamp: Date())
            self.history.insert(transcription, at: 0)
            if self.history.count > self.maxHistoryItems {
                self.history = Array(self.history.prefix(self.maxHistoryItems))
            }

            self.lastError = preservedError
            // Keep the panel open showing the transcript + summary; a second Option
            // tap (or Option+Space) dismisses it. The Option-tap monitor stays active.
            self.state = .reviewing
        }
    }

    /// Closes the live panel, clears the transcript/summary, and returns to idle.
    /// Used both for the second Option tap during review and the immediate close when
    /// nothing was captured.
    func dismissReview() {
        summaryDebounceTask?.cancel()
        summaryDebounceTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        summaryStatus = .idle
        liveText = ""
        partialText = ""
        summaryText = ""
        summaryCache.removeAll()
        hotKeyManager.setListening(false)
        LiveTranscriptionWindowController.shared.hide()
        state = .idle
    }

    /// Called on each finalized segment. We don't summarize immediately — instead we
    /// mark the summary as "waiting" and (re)start a debounce timer so the actual API
    /// call only fires once the speaker pauses (no new segments for `summaryPauseInterval`).
    private func scheduleSummaryAfterPause() {
        guard summaryService != nil else { return }
        guard !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // New speech supersedes any in-flight request and resets the pause timer.
        summaryTask?.cancel()
        summaryTask = nil
        summaryDebounceTask?.cancel()
        summaryStatus = .waiting

        summaryDebounceTask = Task { [weak self] in
            let interval = self?.summaryPauseInterval ?? 1.5
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.runSummary()
        }
    }

    /// Fires the actual summarization API call after a detected pause and streams the
    /// refreshed summary in. The previous summary stays visible until new text arrives.
    private func runSummary() {
        guard let summaryService else { return }
        let transcript = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        let level = summaryLevel
        summaryStatus = .loading
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            do {
                var startedReplacing = false
                for try await chunk in summaryService.summarize(transcript: transcript, level: level) {
                    try Task.checkCancellation()
                    guard let self else { return }
                    // Clear the previous summary only once the new one starts arriving,
                    // so the visible text doesn't blank out during the round-trip.
                    if !startedReplacing {
                        self.summaryText = ""
                        startedReplacing = true
                    }
                    self.summaryText += chunk
                }
                guard let self else { return }
                // Cache the finished result so switching back to this level is instant.
                if self.summaryLevel == level {
                    self.summaryCache[level] = self.summaryText
                }
                self.summaryStatus = .ready
            } catch is CancellationError {
                // Superseded by newer speech — a newer request/timer will take over.
            } catch {
                // Don't surface summary failures as the primary error; transcription
                // is the main flow. Leave the last good summary in place.
                self?.summaryStatus = .ready
            }
        }
    }

    /// Handles a change of `summaryLevel`: stash the current text under the old level,
    /// show any cached text for the new level instantly, then refresh it against the
    /// current transcript.
    private func switchSummaryLevel(from oldLevel: SummaryLevel) {
        guard state == .recording || state == .reviewing else { return }
        if !summaryText.isEmpty {
            summaryCache[oldLevel] = summaryText
        }
        summaryText = summaryCache[summaryLevel] ?? ""

        let transcript = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        runSummary()
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
        finishRecording(preservedError: recordingLimitErrorMessage)
    }

    deinit {
        recordingLimitTask?.cancel()
        streamingTask?.cancel()
        summaryTask?.cancel()
        summaryDebounceTask?.cancel()
    }
}
