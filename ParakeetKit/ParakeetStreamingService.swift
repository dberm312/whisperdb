import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import WhisperDBKit

/// A single transcription update from the streaming recognizer.
///
/// Interim hypotheses arrive with `isFinal == false` and may be revised; once a
/// segment is finalized it is delivered once more with `isFinal == true` and will
/// not change again.
public struct ASRResult: Sendable {
    public let text: String
    public let isFinal: Bool
}

/// Streams microphone audio to NVIDIA's hosted Parakeet CTC 1.1b ASR model
/// (build.nvidia.com) over gRPC (NVIDIA Riva) and yields live transcripts.
///
/// Mirrors the streaming style of `OpenRouterService` — returns an
/// `AsyncThrowingStream` the caller consumes — but the transport is a
/// bidirectional gRPC `StreamingRecognize` call instead of SSE-over-HTTP.
public final class ParakeetStreamingService: Sendable {
    private let apiKey: String

    // Hosted Parakeet CTC 1.1b streaming ASR function on NVIDIA Cloud Functions.
    private let host = "grpc.nvcf.nvidia.com"
    private let port = 443
    private let functionID = "1598d209-5e27-4d3c-8079-4751568b1081"

    // Parakeet expects 16 kHz mono signed 16-bit little-endian PCM.
    public static let sampleRate = 16_000

    public init() throws {
        guard let key = EnvLoader.get("NVIDIA_API_KEY"), !key.isEmpty else {
            throw ParakeetError.missingAPIKey
        }
        self.apiKey = key
    }

    /// Opens a streaming recognition session. Feed raw PCM chunks into `audio`;
    /// finish that stream to signal end-of-speech. The returned stream yields
    /// interim and final transcripts and finishes once the server is done.
    public func transcribe(audio: AsyncStream<Data>) -> AsyncThrowingStream<ASRResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runStream(audio: audio, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        audio: AsyncStream<Data>,
        continuation: AsyncThrowingStream<ASRResult, Error>.Continuation
    ) async throws {
        let transport = try HTTP2ClientTransport.Posix.http2NIOPosix(
            target: .dns(host: host, port: port),
            transportSecurity: .tls
        )

        try await withGRPCClient(transport: transport) { client in
            let asr = Nvidia_Riva_Asr_RivaSpeechRecognition.Client(wrapping: client)

            var metadata = Metadata()
            metadata.addString("Bearer \(self.apiKey)", forKey: "authorization")
            metadata.addString(self.functionID, forKey: "function-id")

            try await asr.streamingRecognize(
                metadata: metadata,
                requestProducer: { writer in
                    // The first request must carry the streaming config, no audio.
                    var config = Nvidia_Riva_Asr_RecognitionConfig()
                    config.encoding = .linearPcm
                    config.sampleRateHertz = Int32(Self.sampleRate)
                    config.languageCode = "en-US"
                    config.maxAlternatives = 1
                    config.audioChannelCount = 1
                    config.enableAutomaticPunctuation = true

                    var streamingConfig = Nvidia_Riva_Asr_StreamingRecognitionConfig()
                    streamingConfig.config = config
                    streamingConfig.interimResults = true

                    var configRequest = Nvidia_Riva_Asr_StreamingRecognizeRequest()
                    configRequest.streamingConfig = streamingConfig
                    try await writer.write(configRequest)

                    // Subsequent requests carry sequential audio chunks.
                    for await chunk in audio {
                        try Task.checkCancellation()
                        var audioRequest = Nvidia_Riva_Asr_StreamingRecognizeRequest()
                        audioRequest.audioContent = chunk
                        try await writer.write(audioRequest)
                    }
                    // Returning closes the request stream → server emits final result.
                },
                onResponse: { response in
                    for try await message in response.messages {
                        for result in message.results {
                            guard let alternative = result.alternatives.first else { continue }
                            let text = alternative.transcript
                            guard !text.isEmpty else { continue }
                            continuation.yield(ASRResult(text: text, isFinal: result.isFinal))
                        }
                    }
                }
            )
        }
    }

    public enum ParakeetError: LocalizedError {
        case missingAPIKey

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "NVIDIA_API_KEY not found. Add it to your .env file"
            }
        }
    }
}
