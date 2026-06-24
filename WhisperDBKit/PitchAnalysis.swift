import AVFoundation
import Accelerate
import Foundation

public struct PitchAnalysisConfiguration: Sendable {
    public var analysisSampleRate: Double
    public var minimumPitchHz: Double
    public var maximumPitchHz: Double
    public var frameDuration: TimeInterval
    public var hopDuration: TimeInterval
    public var minimumFrameRMS: Float
    public var yinThreshold: Double
    public var minimumConfidence: Double
    public var medianFilterRadius: Int
    public var octaveJumpCents: Double
    public var endingWindowDuration: TimeInterval
    public var minimumVoicedFramesForSummary: Int
    public var significantTrendCents: Double

    public init(
        analysisSampleRate: Double = 16_000,
        minimumPitchHz: Double = 50,
        maximumPitchHz: Double = 800,
        frameDuration: TimeInterval = 0.04,
        hopDuration: TimeInterval = 0.01,
        minimumFrameRMS: Float = 0.005,
        yinThreshold: Double = 0.15,
        minimumConfidence: Double = 0.7,
        medianFilterRadius: Int = 2,
        octaveJumpCents: Double = 700,
        endingWindowDuration: TimeInterval = 1.5,
        minimumVoicedFramesForSummary: Int = 6,
        significantTrendCents: Double = 100
    ) {
        self.analysisSampleRate = analysisSampleRate
        self.minimumPitchHz = minimumPitchHz
        self.maximumPitchHz = maximumPitchHz
        self.frameDuration = frameDuration
        self.hopDuration = hopDuration
        self.minimumFrameRMS = minimumFrameRMS
        self.yinThreshold = yinThreshold
        self.minimumConfidence = minimumConfidence
        self.medianFilterRadius = medianFilterRadius
        self.octaveJumpCents = octaveJumpCents
        self.endingWindowDuration = endingWindowDuration
        self.minimumVoicedFramesForSummary = minimumVoicedFramesForSummary
        self.significantTrendCents = significantTrendCents
    }
}

public struct PitchFrame: Equatable, Sendable {
    public let time: TimeInterval
    public var hz: Double?
    public var confidence: Double
    public let rms: Float

    public init(time: TimeInterval, hz: Double?, confidence: Double, rms: Float) {
        self.time = time
        self.hz = hz
        self.confidence = confidence
        self.rms = rms
    }
}

public struct PitchFrequencyRange: Equatable, Sendable {
    public let minHz: Double
    public let maxHz: Double

    public init(minHz: Double, maxHz: Double) {
        self.minHz = minHz
        self.maxHz = maxHz
    }
}

public enum PitchTrendLabel: String, Equatable, Sendable {
    case insufficientEvidence = "insufficient evidence"
    case steady
    case risingEnding = "rising ending"
    case fallingEnding = "falling ending"
}

public struct PitchSummary: Equatable, Sendable {
    public let startMedianHz: Double?
    public let endingMedianHz: Double?
    public let deltaCents: Double?
    public let trendLabel: PitchTrendLabel
    public let evidenceRangeHz: PitchFrequencyRange?
    public let scoredRangeHz: PitchFrequencyRange?

    public init(
        startMedianHz: Double?,
        endingMedianHz: Double?,
        deltaCents: Double?,
        trendLabel: PitchTrendLabel,
        evidenceRangeHz: PitchFrequencyRange?,
        scoredRangeHz: PitchFrequencyRange?
    ) {
        self.startMedianHz = startMedianHz
        self.endingMedianHz = endingMedianHz
        self.deltaCents = deltaCents
        self.trendLabel = trendLabel
        self.evidenceRangeHz = evidenceRangeHz
        self.scoredRangeHz = scoredRangeHz
    }

    static let empty = PitchSummary(
        startMedianHz: nil,
        endingMedianHz: nil,
        deltaCents: nil,
        trendLabel: .insufficientEvidence,
        evidenceRangeHz: nil,
        scoredRangeHz: nil
    )
}

public struct PitchContour: Equatable, Sendable {
    public let frames: [PitchFrame]
    public let summary: PitchSummary

    public init(frames: [PitchFrame], summary: PitchSummary) {
        self.frames = frames
        self.summary = summary
    }
}

public enum PitchAnalysisError: LocalizedError {
    case unableToCreateAudioFormat
    case unableToCreateAudioBuffer
    case unableToReadAudio(Error)
    case audioConversionFailed(Error?)
    case noDecodedSamples

    public var errorDescription: String? {
        switch self {
        case .unableToCreateAudioFormat:
            return "Could not create the pitch analysis audio format."
        case .unableToCreateAudioBuffer:
            return "Could not allocate an audio buffer for pitch analysis."
        case .unableToReadAudio(let error):
            return "Could not read audio for pitch analysis: \(error.localizedDescription)"
        case .audioConversionFailed(let error):
            if let error {
                return "Could not convert audio for pitch analysis: \(error.localizedDescription)"
            }
            return "Could not convert audio for pitch analysis."
        case .noDecodedSamples:
            return "No audio samples were available for pitch analysis."
        }
    }
}

public enum PitchAnalyzer {
    public static func analyze(
        audioURL: URL,
        configuration: PitchAnalysisConfiguration = PitchAnalysisConfiguration()
    ) throws -> PitchContour {
        let samples = try decodeMonoSamples(from: audioURL, targetSampleRate: configuration.analysisSampleRate)
        return analyze(samples: samples, sampleRate: configuration.analysisSampleRate, configuration: configuration)
    }

    public static func analyze(
        samples: [Float],
        sampleRate: Double,
        configuration: PitchAnalysisConfiguration = PitchAnalysisConfiguration()
    ) -> PitchContour {
        guard
            !samples.isEmpty,
            sampleRate > 0,
            configuration.minimumPitchHz > 0,
            configuration.maximumPitchHz > configuration.minimumPitchHz
        else {
            return PitchContour(frames: [], summary: .empty)
        }

        let frameLength = max(1, Int((configuration.frameDuration * sampleRate).rounded()))
        let hopLength = max(1, Int((configuration.hopDuration * sampleRate).rounded()))
        guard samples.count >= frameLength else {
            return PitchContour(frames: [], summary: .empty)
        }

        let filteredSamples = filterForSpeechPitch(
            samples,
            sampleRate: sampleRate,
            highPassHz: configuration.minimumPitchHz,
            lowPassHz: configuration.maximumPitchHz
        )

        var frames: [PitchFrame] = []
        var start = 0
        while start + frameLength <= filteredSamples.count {
            let rms = rootMeanSquare(filteredSamples, start: start, count: frameLength)
            let time = Double(start) / sampleRate

            guard rms >= configuration.minimumFrameRMS else {
                frames.append(PitchFrame(time: time, hz: nil, confidence: 0, rms: rms))
                start += hopLength
                continue
            }

            if let estimate = estimatePitch(
                in: filteredSamples,
                start: start,
                frameLength: frameLength,
                sampleRate: sampleRate,
                configuration: configuration
            ) {
                frames.append(
                    PitchFrame(time: time, hz: estimate.hz, confidence: estimate.confidence, rms: rms)
                )
            } else {
                frames.append(PitchFrame(time: time, hz: nil, confidence: 0, rms: rms))
            }

            start += hopLength
        }

        let cleanedFrames = clean(frames: frames, configuration: configuration)
        return PitchContour(
            frames: cleanedFrames,
            summary: summarize(frames: cleanedFrames, configuration: configuration)
        )
    }
}

extension PitchAnalyzer {
    static func clean(frames: [PitchFrame], configuration: PitchAnalysisConfiguration) -> [PitchFrame] {
        guard !frames.isEmpty else { return frames }

        let radius = max(1, configuration.medianFilterRadius)
        var octaveCorrected = frames

        for index in octaveCorrected.indices {
            guard let hz = octaveCorrected[index].hz else { continue }
            let neighborHz = voicedValues(around: index, in: octaveCorrected, radius: radius, excludingCenter: true)
            guard neighborHz.count >= 2, let localMedian = median(neighborHz) else { continue }

            if abs(centsBetween(hz, localMedian)) > configuration.octaveJumpCents {
                octaveCorrected[index].hz = localMedian
                octaveCorrected[index].confidence *= 0.8
            }
        }

        guard configuration.medianFilterRadius > 0 else { return octaveCorrected }

        var smoothed = octaveCorrected
        for index in smoothed.indices {
            guard smoothed[index].hz != nil else { continue }
            let localValues = voicedValues(around: index, in: octaveCorrected, radius: radius, excludingCenter: false)
            guard localValues.count >= 2, let localMedian = median(localValues) else { continue }
            smoothed[index].hz = localMedian
        }

        return smoothed
    }

    static func summarize(frames: [PitchFrame], configuration: PitchAnalysisConfiguration) -> PitchSummary {
        let voiced = frames.compactMap { frame -> (time: TimeInterval, hz: Double)? in
            guard let hz = frame.hz else { return nil }
            return (frame.time, hz)
        }

        let evidenceRange = frequencyRange(voiced.map(\.hz))
        guard voiced.count >= configuration.minimumVoicedFramesForSummary else {
            return PitchSummary(
                startMedianHz: nil,
                endingMedianHz: nil,
                deltaCents: nil,
                trendLabel: .insufficientEvidence,
                evidenceRangeHz: evidenceRange,
                scoredRangeHz: nil
            )
        }

        let lastTime = frames.last?.time ?? voiced.last?.time ?? 0
        let endingStart = max(0, lastTime - configuration.endingWindowDuration)
        let minimumWindowCount = max(2, configuration.minimumVoicedFramesForSummary / 3)

        var earlier = voiced.filter { $0.time < endingStart }
        if earlier.count < minimumWindowCount {
            earlier = Array(voiced.prefix(max(minimumWindowCount, voiced.count * 3 / 5)))
        }

        var ending = voiced.filter { $0.time >= endingStart }
        if ending.count < minimumWindowCount {
            ending = Array(voiced.suffix(max(minimumWindowCount, voiced.count / 4)))
        }

        guard
            let startMedian = median(earlier.map(\.hz)),
            let endingMedian = median(ending.map(\.hz)),
            startMedian > 0,
            endingMedian > 0
        else {
            return PitchSummary(
                startMedianHz: nil,
                endingMedianHz: nil,
                deltaCents: nil,
                trendLabel: .insufficientEvidence,
                evidenceRangeHz: evidenceRange,
                scoredRangeHz: nil
            )
        }

        let deltaCents = centsBetween(endingMedian, startMedian)
        let trendLabel: PitchTrendLabel
        if deltaCents >= configuration.significantTrendCents {
            trendLabel = .risingEnding
        } else if deltaCents <= -configuration.significantTrendCents {
            trendLabel = .fallingEnding
        } else {
            trendLabel = .steady
        }

        return PitchSummary(
            startMedianHz: startMedian,
            endingMedianHz: endingMedian,
            deltaCents: deltaCents,
            trendLabel: trendLabel,
            evidenceRangeHz: evidenceRange,
            scoredRangeHz: frequencyRange(earlier.map(\.hz) + ending.map(\.hz))
        )
    }
}

extension PitchAnalyzer {
    fileprivate struct PitchEstimate {
        let hz: Double
        let confidence: Double
    }

    fileprivate static func decodeMonoSamples(from audioURL: URL, targetSampleRate: Double) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: audioURL)
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw PitchAnalysisError.unableToCreateAudioFormat
        }

        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
            throw PitchAnalysisError.unableToCreateAudioFormat
        }

        let estimatedOutputFrames = AVAudioFrameCount(
            max(1, ceil(Double(inputFile.length) * targetSampleRate / inputFile.processingFormat.sampleRate))
        )
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: estimatedOutputFrames + 1024
            )
        else {
            throw PitchAnalysisError.unableToCreateAudioBuffer
        }

        var didProvideInput = false
        var readError: Error?
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard !didProvideInput else {
                outStatus.pointee = .endOfStream
                return nil
            }

            guard
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFile.processingFormat,
                    frameCapacity: AVAudioFrameCount(inputFile.length)
                )
            else {
                outStatus.pointee = .noDataNow
                readError = PitchAnalysisError.unableToCreateAudioBuffer
                return nil
            }

            do {
                try inputFile.read(into: inputBuffer)
                didProvideInput = true
                outStatus.pointee = inputBuffer.frameLength > 0 ? .haveData : .endOfStream
                return inputBuffer
            } catch {
                readError = error
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        if let readError {
            throw PitchAnalysisError.unableToReadAudio(readError)
        }

        if status == .error || conversionError != nil {
            throw PitchAnalysisError.audioConversionFailed(conversionError)
        }

        guard let channelData = outputBuffer.floatChannelData?[0], outputBuffer.frameLength > 0 else {
            throw PitchAnalysisError.noDecodedSamples
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }

    fileprivate static func filterForSpeechPitch(
        _ samples: [Float],
        sampleRate: Double,
        highPassHz: Double,
        lowPassHz: Double
    ) -> [Float] {
        let highPassed = onePoleHighPass(samples, sampleRate: sampleRate, cutoffHz: highPassHz)
        return onePoleLowPass(highPassed, sampleRate: sampleRate, cutoffHz: lowPassHz)
    }

    fileprivate static func onePoleHighPass(_ samples: [Float], sampleRate: Double, cutoffHz: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0, cutoffHz > 0 else { return samples }

        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * Double.pi * cutoffHz)
        let alpha = Float(rc / (rc + dt))

        var output = [Float](repeating: 0, count: samples.count)
        var previousInput = samples[0]
        var previousOutput: Float = 0

        for index in samples.indices {
            let value = alpha * (previousOutput + samples[index] - previousInput)
            output[index] = value
            previousInput = samples[index]
            previousOutput = value
        }

        return output
    }

    fileprivate static func onePoleLowPass(_ samples: [Float], sampleRate: Double, cutoffHz: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0, cutoffHz > 0 else { return samples }

        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * Double.pi * cutoffHz)
        let alpha = Float(dt / (rc + dt))

        var output = [Float](repeating: 0, count: samples.count)
        var previousOutput = samples[0]

        for index in samples.indices {
            previousOutput += alpha * (samples[index] - previousOutput)
            output[index] = previousOutput
        }

        return output
    }

    fileprivate static func rootMeanSquare(_ samples: [Float], start: Int, count: Int) -> Float {
        guard count > 0 else { return 0 }

        var meanSquare: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            vDSP_measqv(baseAddress.advanced(by: start), 1, &meanSquare, vDSP_Length(count))
        }

        return sqrt(meanSquare)
    }

    fileprivate static func estimatePitch(
        in samples: [Float],
        start: Int,
        frameLength: Int,
        sampleRate: Double,
        configuration: PitchAnalysisConfiguration
    ) -> PitchEstimate? {
        let minTau = max(2, Int(floor(sampleRate / configuration.maximumPitchHz)))
        let maxTau = min(frameLength - 2, Int(ceil(sampleRate / configuration.minimumPitchHz)))
        guard maxTau > minTau else { return nil }

        let difference = yinDifference(
            samples: samples,
            start: start,
            frameLength: frameLength,
            maxTau: maxTau
        )

        var cumulativeMeanNormalized = [Double](repeating: 1, count: maxTau + 1)
        var runningSum: Double = 0
        for tau in 1...maxTau {
            runningSum += difference[tau]
            guard runningSum > 0 else { continue }
            cumulativeMeanNormalized[tau] = difference[tau] * Double(tau) / runningSum
        }

        var chosenTau: Int?
        var tau = minTau
        while tau <= maxTau {
            if cumulativeMeanNormalized[tau] < configuration.yinThreshold {
                while tau + 1 <= maxTau
                    && cumulativeMeanNormalized[tau + 1] < cumulativeMeanNormalized[tau]
                {
                    tau += 1
                }
                chosenTau = tau
                break
            }
            tau += 1
        }

        if chosenTau == nil {
            let bestTau = (minTau...maxTau).min {
                cumulativeMeanNormalized[$0] < cumulativeMeanNormalized[$1]
            }
            if let bestTau, 1.0 - cumulativeMeanNormalized[bestTau] >= configuration.minimumConfidence {
                chosenTau = bestTau
            }
        }

        guard let chosenTau else { return nil }

        let confidence = max(0, min(1, 1.0 - cumulativeMeanNormalized[chosenTau]))
        guard confidence >= configuration.minimumConfidence else { return nil }

        let refinedTau = parabolicInterpolatedTau(
            chosenTau,
            values: cumulativeMeanNormalized,
            lowerBound: minTau,
            upperBound: maxTau
        )
        guard refinedTau > 0 else { return nil }

        let hz = sampleRate / refinedTau
        guard hz >= configuration.minimumPitchHz, hz <= configuration.maximumPitchHz else {
            return nil
        }

        return PitchEstimate(hz: hz, confidence: confidence)
    }

    fileprivate static func yinDifference(samples: [Float], start: Int, frameLength: Int, maxTau: Int) -> [Double] {
        var prefixEnergy = [Float](repeating: 0, count: frameLength + 1)
        for index in 0..<frameLength {
            let sample = samples[start + index]
            prefixEnergy[index + 1] = prefixEnergy[index] + sample * sample
        }

        var difference = [Double](repeating: 0, count: maxTau + 1)
        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let frameBase = baseAddress.advanced(by: start)

            for tau in 1...maxTau {
                let limit = frameLength - tau
                var dotProduct: Float = 0
                vDSP_dotpr(
                    frameBase,
                    1,
                    frameBase.advanced(by: tau),
                    1,
                    &dotProduct,
                    vDSP_Length(limit)
                )

                let firstEnergy = prefixEnergy[limit]
                let shiftedEnergy = prefixEnergy[tau + limit] - prefixEnergy[tau]
                let value = max(0, firstEnergy + shiftedEnergy - 2 * dotProduct)
                difference[tau] = Double(value)
            }
        }

        return difference
    }

    fileprivate static func parabolicInterpolatedTau(
        _ tau: Int,
        values: [Double],
        lowerBound: Int,
        upperBound: Int
    ) -> Double {
        guard tau > lowerBound, tau < upperBound else { return Double(tau) }

        let left = values[tau - 1]
        let center = values[tau]
        let right = values[tau + 1]
        let denominator = left - 2.0 * center + right
        guard abs(denominator) > .ulpOfOne else { return Double(tau) }

        return Double(tau) + 0.5 * (left - right) / denominator
    }

    fileprivate static func voicedValues(
        around index: Int,
        in frames: [PitchFrame],
        radius: Int,
        excludingCenter: Bool
    ) -> [Double] {
        let lowerBound = max(0, index - radius)
        let upperBound = min(frames.count - 1, index + radius)

        return (lowerBound...upperBound).compactMap { frameIndex in
            guard !excludingCenter || frameIndex != index else { return nil }
            return frames[frameIndex].hz
        }
    }

    fileprivate static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }

        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2.0
        }
        return sortedValues[middleIndex]
    }

    fileprivate static func frequencyRange(_ values: [Double]) -> PitchFrequencyRange? {
        guard let minHz = values.min(), let maxHz = values.max() else { return nil }
        return PitchFrequencyRange(minHz: minHz, maxHz: maxHz)
    }

    fileprivate static func centsBetween(_ hz: Double, _ referenceHz: Double) -> Double {
        guard hz > 0, referenceHz > 0 else { return 0 }
        return 1_200.0 * log2(hz / referenceHz)
    }
}
