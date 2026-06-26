import Foundation

/// Streams a continuously-refreshed, organized summary of a running transcript from
/// NVIDIA's hosted DiffusionGemma model. The endpoint is OpenAI-compatible, so the
/// request/SSE handling mirrors `OpenRouterService`.
public final class NvidiaSummaryService {
    private let apiKey: String
    private let baseURL = "https://integrate.api.nvidia.com/v1/chat/completions"
    private let model = "google/diffusiongemma-26b-a4b-it"

    public init() throws {
        // Prefer a dedicated key if present, otherwise reuse the NVIDIA key already
        // required for Parakeet — the same nvapi- key works for integrate.api.nvidia.com.
        let key = EnvLoader.get("NVIDIA_SUMMARY_API_KEY") ?? EnvLoader.get("NVIDIA_API_KEY")
        guard let key, !key.isEmpty else {
            throw NvidiaSummaryError.missingAPIKey
        }
        self.apiKey = key
    }

    private let systemPrompt = """
        You are turning a running voice transcript into a concise, well organized live \
        digest for the person who is speaking. Reformat everything said so far into clean \
        markdown: use a bulleted list for to-dos or enumerated items, numbered sections \
        for distinct topics, short headings when the content clearly spans different \
        topics, and short plain paragraphs otherwise. Keep it tight and skimmable. \
        Capture only what was actually said — do not add information, do not invent \
        details, and do not include any preamble, commentary, or closing remarks. \
        Output only the organized markdown.
        """

    public func summarize(transcript: String) -> AsyncThrowingStream<String, Error> {
        stream(messages: [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript],
        ])
    }

    private func stream(messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.buildRequest(messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NvidiaSummaryError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw NvidiaSummaryError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let choices = json["choices"] as? [[String: Any]],
                            let delta = choices.first?["delta"] as? [String: Any],
                            let content = delta["content"] as? String
                        else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func buildRequest(messages: [[String: String]]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": 1024,
            "messages": messages,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public enum NvidiaSummaryError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "NVIDIA_API_KEY not found. Add it to your .env file"
            case .invalidResponse:
                return "Invalid response from NVIDIA API"
            case .apiError(let code, let message):
                return "NVIDIA API error (\(code)): \(message)"
            }
        }
    }
}
