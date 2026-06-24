import XCTest

@testable import WhisperDBKit

final class PitchAnalysisTests: XCTestCase {
    private let sampleRate: Double = 16_000

    func testDetectsGeneratedSinePitches() {
        for targetHz in [100.0, 200.0, 400.0] {
            let samples = sineWave(hz: targetHz, duration: 1.0)
            let contour = PitchAnalyzer.analyze(
                samples: samples,
                sampleRate: sampleRate,
                configuration: testConfiguration()
            )

            let medianHz = median(contour.frames.compactMap(\.hz))
            XCTAssertNotNil(medianHz)
            XCTAssertEqual(medianHz ?? 0, targetHz, accuracy: targetHz * 0.03)
        }
    }

    func testSilenceReturnsUnvoicedFrames() {
        let samples = [Float](repeating: 0, count: Int(sampleRate))
        let contour = PitchAnalyzer.analyze(
            samples: samples,
            sampleRate: sampleRate,
            configuration: testConfiguration()
        )

        XCTAssertFalse(contour.frames.isEmpty)
        XCTAssertTrue(contour.frames.allSatisfy { $0.hz == nil })
        XCTAssertEqual(contour.summary.trendLabel, .insufficientEvidence)
    }

    func testMedianCleanupSuppressesInjectedOctaveOutlier() {
        var frames = (0..<21).map { index in
            PitchFrame(time: Double(index) * 0.01, hz: 200, confidence: 0.95, rms: 0.15)
        }
        frames[10].hz = 400

        let cleanedFrames = PitchAnalyzer.clean(frames: frames, configuration: testConfiguration())

        XCTAssertEqual(cleanedFrames[10].hz ?? 0, 200, accuracy: 0.001)
    }

    func testRisingEndingUsesMedianTrendInsteadOfSingleOutlier() {
        var frames = (0..<240).map { index -> PitchFrame in
            let time = Double(index) * 0.01
            let hz = time < 1.6 ? 160.0 : 185.0
            return PitchFrame(time: time, hz: hz, confidence: 0.9, rms: 0.12)
        }
        frames[220].hz = 420

        let configuration = testConfiguration(endingWindowDuration: 0.7)
        let cleanedFrames = PitchAnalyzer.clean(frames: frames, configuration: configuration)
        let summary = PitchAnalyzer.summarize(frames: cleanedFrames, configuration: configuration)

        XCTAssertEqual(summary.trendLabel, .risingEnding)
        XCTAssertEqual(summary.startMedianHz ?? 0, 160, accuracy: 0.001)
        XCTAssertEqual(summary.endingMedianHz ?? 0, 185, accuracy: 0.001)
    }

    private func testConfiguration(
        endingWindowDuration: TimeInterval = 0.5
    ) -> PitchAnalysisConfiguration {
        PitchAnalysisConfiguration(
            analysisSampleRate: sampleRate,
            minimumPitchHz: 50,
            maximumPitchHz: 800,
            frameDuration: 0.04,
            hopDuration: 0.01,
            minimumFrameRMS: 0.002,
            yinThreshold: 0.15,
            minimumConfidence: 0.65,
            medianFilterRadius: 2,
            octaveJumpCents: 700,
            endingWindowDuration: endingWindowDuration,
            minimumVoicedFramesForSummary: 6,
            significantTrendCents: 100
        )
    }

    private func sineWave(hz: Double, duration: TimeInterval) -> [Float] {
        let sampleCount = Int(sampleRate * duration)
        return (0..<sampleCount).map { index in
            Float(0.45 * sin(2.0 * Double.pi * hz * Double(index) / sampleRate))
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2.0
        }
        return sortedValues[middleIndex]
    }
}
