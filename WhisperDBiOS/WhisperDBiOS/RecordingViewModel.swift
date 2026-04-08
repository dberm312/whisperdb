import ActivityKit
import AVFoundation
import SwiftUI
import WhisperDBKit

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcription = ""
    @Published var error: String?
    @Published var audioLevel: Float = 0
    @Published var copied = false
    @Published var recordingElapsedTime: TimeInterval = 0
    @Published var showLimitAlert = false
    @Published var history: [HistoryItem] = []

    let maxRecordingDuration: TimeInterval = 15 * 60

    private let recorder = AudioRecorderIOS()
    private var groqService: GroqService?
    private var recordingStartedAt: Date?
    private var recordingLimitTask: Task<Void, Never>?
    private var liveActivity: Any?
    private var lastReportedSeconds: Int = -1

    private static let historyKey = "whisperdb_history"

    var formattedElapsedTime: String {
        let totalSeconds = max(0, Int(recordingElapsedTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedMaxDuration: String {
        let totalSeconds = Int(maxRecordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init() {
        do {
            groqService = try GroqService()
        } catch {
            self.error = error.localizedDescription
        }
        loadHistory()
    }

    func toggleRecording() {
        if isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    func stopIfRecording() {
        guard isRecording else { return }
        stopAndTranscribe()
    }

    private func startRecording() {
        error = nil

        Task {
            do {
                let granted = await requestMicPermission()
                guard granted else {
                    error = "Microphone access denied. Enable in Settings > Privacy > Microphone."
                    return
                }

                // Validate Groq service is ready before starting
                guard groqService != nil else {
                    error = "Groq API not configured. Check your API key."
                    return
                }

                try recorder.startRecording()

                // Verify audio engine is actually producing data
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms warm-up
                guard recorder.isEngineRunning else {
                    recorder.stopRecording()
                    error = "Audio engine failed to start. Please try again."
                    return
                }

                isRecording = true
                recordingStartedAt = Date()
                lastReportedSeconds = -1
                scheduleRecordingLimitTask()
                startLiveActivity()

                // Poll audio level and elapsed time
                while isRecording {
                    audioLevel = recorder.audioLevel
                    if let start = recordingStartedAt {
                        recordingElapsedTime = Date().timeIntervalSince(start)
                    }
                    updateLiveActivity()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            } catch {
                self.error = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    private func stopAndTranscribe(preservedError: String? = nil) {
        isRecording = false
        recordingElapsedTime = 0
        recordingStartedAt = nil
        cancelRecordingLimitTask()
        endLiveActivity()

        guard let audioURL = recorder.stopRecording() else {
            error = preservedError ?? "No audio recorded"
            return
        }

        // Validate the audio file has actual content
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        if fileSize < 1000 {
            error = "Recording was too short or empty. Please try again."
            recorder.cleanup()
            return
        }

        if let preservedError {
            error = preservedError
        }

        isProcessing = true

        Task {
            defer {
                isProcessing = false
                recorder.cleanup()
            }

            guard let service = groqService else {
                error = "Groq API not configured"
                return
            }

            do {
                let text = try await service.transcribe(audioURL: audioURL)
                transcription = text
                addToHistory(text: text)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - History

    struct HistoryItem: Codable, Identifiable {
        let id: UUID
        let text: String
        let timestamp: Date

        init(text: String) {
            self.id = UUID()
            self.text = text
            self.timestamp = Date()
        }

        var timeAgo: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: timestamp, relativeTo: Date())
        }
    }

    private func addToHistory(text: String) {
        let item = HistoryItem(text: text)
        history.insert(item, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        saveHistory()
    }

    func deleteHistoryItem(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
    }

    func deleteHistoryItem(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        history = items
    }

    // MARK: - Recording Limit

    private func scheduleRecordingLimitTask() {
        recordingLimitTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(maxRecordingDuration * 1_000_000_000))
            guard !Task.isCancelled, isRecording else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showLimitAlert = true
            stopAndTranscribe(preservedError: "Recording stopped at 15 minutes to prevent accidental over-recording.")
        }
    }

    private func cancelRecordingLimitTask() {
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingAttributes(maxDurationSeconds: Int(maxRecordingDuration))
        let state = RecordingAttributes.ContentState(elapsedSeconds: 0, isRecording: true)
        let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        liveActivity = activity
    }

    private func updateLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = liveActivity as? Activity<RecordingAttributes> else { return }
        let newSeconds = Int(recordingElapsedTime)
        guard newSeconds != lastReportedSeconds else { return }
        lastReportedSeconds = newSeconds
        let state = RecordingAttributes.ContentState(elapsedSeconds: newSeconds, isRecording: true)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = liveActivity as? Activity<RecordingAttributes> else { return }
        let finalState = RecordingAttributes.ContentState(elapsedSeconds: Int(recordingElapsedTime), isRecording: false)
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }

    func showCopied() {
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
