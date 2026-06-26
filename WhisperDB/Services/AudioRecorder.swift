import AVFoundation
import AudioToolbox
import Foundation

final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0

    private var peakAudioLevel: Float = 0.0
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private(set) var recordingURL: URL?

    // Streaming (live transcription) state. When set, captured audio is resampled
    // to 16 kHz mono Int16 PCM and delivered to `onPCMChunk` instead of a file.
    private var pcmConverter: AVAudioConverter?
    private var onPCMChunk: ((Data) -> Void)?
    private let streamFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    func startRecording(selectedDeviceUID: String? = nil) throws {
        peakAudioLevel = 0.0
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let selectedDeviceUID,
            let deviceID = CoreAudioInputDevices.deviceID(forUID: selectedDeviceUID)
        {
            try setInputDevice(deviceID, on: inputNode)
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Record as m4a (AAC) — compact and universally supported by Whisper
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

            // Compute RMS audio level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            // Normalize to 0–1 range (clamp, typical speech RMS is 0.01–0.2)
            let normalized = min(max(rms * 5.0, 0.0), 1.0)

            self?.peakAudioLevel = max(self?.peakAudioLevel ?? 0, normalized)

            DispatchQueue.main.async {
                self?.audioLevel = normalized
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isRecording = true
    }

    /// Live-streaming capture. Resamples the microphone input to 16 kHz mono
    /// Int16 PCM and hands each chunk to `onPCM` (for NVIDIA Parakeet streaming
    /// ASR). No audio file is written. Audio-level metering is preserved so the
    /// status bar animation keeps working.
    func startStreaming(selectedDeviceUID: String? = nil, onPCM: @escaping (Data) -> Void) throws {
        peakAudioLevel = 0.0
        recordingURL = nil
        onPCMChunk = onPCM

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let selectedDeviceUID,
            let deviceID = CoreAudioInputDevices.deviceID(forUID: selectedDeviceUID)
        {
            try setInputDevice(deviceID, on: inputNode)
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: streamFormat) else {
            throw AudioRecorderError.streamingConverterUnavailable
        }
        pcmConverter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.updateAudioLevel(from: buffer)
            self?.convertAndEmit(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isRecording = true
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(max(frameLength, 1)))
        let normalized = min(max(rms * 5.0, 0.0), 1.0)
        peakAudioLevel = max(peakAudioLevel, normalized)
        DispatchQueue.main.async {
            self.audioLevel = normalized
        }
    }

    private func convertAndEmit(buffer: AVAudioPCMBuffer) {
        guard let converter = pcmConverter, let onPCMChunk else { return }

        let ratio = streamFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: streamFormat, frameCapacity: capacity) else {
            return
        }

        var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, outBuffer.frameLength > 0,
            let int16Data = outBuffer.int16ChannelData
        else { return }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Data[0], count: byteCount)
        onPCMChunk(data)
    }

    func getPeakAudioLevel() -> Float {
        return peakAudioLevel
    }

    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        pcmConverter = nil
        onPCMChunk = nil
        isRecording = false
        audioLevel = 0.0
        peakAudioLevel = 0.0
        return recordingURL
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on inputNode: AVAudioInputNode) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioRecorderError.inputDeviceSelectionUnavailable
        }

        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioRecorderError.failedToSelectInputDevice(status: status)
        }
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}

private enum AudioRecorderError: LocalizedError {
    case inputDeviceSelectionUnavailable
    case failedToSelectInputDevice(status: OSStatus)
    case streamingConverterUnavailable

    var errorDescription: String? {
        switch self {
        case .inputDeviceSelectionUnavailable:
            return "Microphone selection is unavailable on this Mac."
        case .failedToSelectInputDevice(let status):
            return "Failed to use the selected microphone (\(status))."
        case .streamingConverterUnavailable:
            return "Could not set up audio conversion for live transcription."
        }
    }
}
