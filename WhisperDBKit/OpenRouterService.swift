import Foundation

public final class OpenRouterService {
    private let apiKey: String
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    private let model = "anthropic/claude-opus-4"

    private let systemPrompt = """
        You are an expert at organizing unstructured text. The user will provide a raw voice \
        transcription. Restructure it into a clean, well-organized markdown document. Add \
        appropriate headings, bullet points, numbered lists, and logical sections. Fix grammar \
        and remove filler words (um, uh, like, you know) while preserving all meaningful content. \
        Do not add information that wasn't in the original. Output only the organized markdown.
        """

    public init() throws {
        guard let key = EnvLoader.get("OPENROUTER_API_KEY"), !key.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        self.apiKey = key
    }

    public func organize(text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try self.buildRequest(text: text)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenRouterError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw OpenRouterError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildRequest(text: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public enum OpenRouterError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OPENROUTER_API_KEY not found. Add it to your .env file"
            case .invalidResponse:
                return "Invalid response from OpenRouter API"
            case .apiError(let code, let message):
                return "OpenRouter API error (\(code)): \(message)"
            }
        }
    }
}
