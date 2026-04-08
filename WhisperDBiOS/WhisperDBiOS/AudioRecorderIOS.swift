import AVFoundation
import Foundation

final class AudioRecorderIOS {
    private(set) var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private(set) var recordingURL: URL?

    var isEngineRunning: Bool {
        audioEngine?.isRunning ?? false
    }

    func startRecording() throws {
        // Tear down any previous engine state to avoid stale taps
        if let existingEngine = audioEngine {
            existingEngine.inputNode.removeTap(onBus: 0)
            existingEngine.stop()
            audioEngine = nil
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        // Create engine after audio session is active so inputNode format is valid
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Guard against zero-sample-rate format (happens on first launch after permission grant)
        guard recordingFormat.sampleRate > 0 else {
            throw RecordingError.invalidAudioFormat
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("whisperdb_\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)
        audioFile = file

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            try? file.write(from: buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            let normalized = min(max(rms * 5.0, 0.0), 1.0)
            self?.audioLevel = normalized
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    enum RecordingError: LocalizedError {
        case invalidAudioFormat

        var errorDescription: String? {
            switch self {
            case .invalidAudioFormat:
                return "Audio input not ready. Please try again."
            }
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        audioLevel = 0

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        return recordingURL
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
