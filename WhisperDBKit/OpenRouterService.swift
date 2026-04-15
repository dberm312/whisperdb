import Foundation

public enum CleanupIntensity: String, CaseIterable, Hashable, Sendable, Identifiable {
    case light
    case medium
    case heavy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    public var subtitle: String {
        switch self {
        case .light: return "Near-verbatim cleanup"
        case .medium: return "Restructure, keep voice"
        case .heavy: return "Full markdown rewrite"
        }
    }

    public var systemSymbol: String {
        switch self {
        case .light: return "feather"
        case .medium: return "wand.and.stars"
        case .heavy: return "sparkles"
        }
    }
}

public final class OpenRouterService {
    private let apiKey: String
    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    // TODO: Light intensity could swap to a lighter/cheaper model in the future.
    private let model = "anthropic/claude-opus-4-6"

    public init() throws {
        guard let key = EnvLoader.get("OPENROUTER_API_KEY"), !key.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        self.apiKey = key
    }

    private func systemPrompt(for intensity: CleanupIntensity) -> String {
        switch intensity {
        case .light:
            return """
                You are cleaning up a raw voice transcription with the lightest possible touch. \
                Preserve the speaker's exact wording — do NOT rephrase, summarize, or remove filler words. \
                Your only jobs: add paragraph breaks where natural pauses occur, fix obvious punctuation and \
                capitalization, and convert content into a bulleted list ONLY when the speaker explicitly \
                enumerates items ("first… second… third…"). Do not add headings. Do not reorder sentences. \
                Do not add anything. Output the cleaned text as plain markdown, preserving the original voice.
                """
        case .medium:
            return """
                You are lightly editing a raw voice transcription. Keep the speaker's voice, tone, and all \
                substantive content intact. Remove filler words (um, uh, like, you know, I mean) and false \
                starts. You may reorder sentences within a paragraph for clarity, and add short section \
                headings only when the content clearly spans distinct topics. Do NOT convert prose into \
                bullet lists unless the speaker was explicitly listing. Do not add information that wasn't \
                in the original. Output clean markdown.
                """
        case .heavy:
            return """
                You are an expert at organizing unstructured text. The user will provide a raw voice \
                transcription. Restructure it into a clean, well-organized markdown document. Add \
                appropriate headings, bullet points, numbered lists, and logical sections. Fix grammar \
                and remove filler words (um, uh, like, you know) while preserving all meaningful content. \
                Do not add information that wasn't in the original. Output only the organized markdown.
                """
        }
    }

    public func organize(text: String, intensity: CleanupIntensity) -> AsyncThrowingStream<String, Error> {
        stream(messages: [
            ["role": "system", "content": systemPrompt(for: intensity)],
            ["role": "user", "content": text],
        ])
    }

    public func refine(
        originalText: String,
        currentOutput: String,
        instruction: String,
        intensity: CleanupIntensity
    ) -> AsyncThrowingStream<String, Error> {
        let system = systemPrompt(for: intensity) + "\n\n" + """
            You previously produced a cleaned version of the transcription. The user will now give you an \
            instruction describing a change they want. Apply that change while continuing to obey the \
            cleanup style described above. Output the full revised document — not just the changed parts.
            """

        let userContent = """
            Original transcription:
            \(originalText)

            Current cleaned version:
            \(currentOutput)

            Change to apply:
            \(instruction)
            """

        return stream(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent],
        ])
    }

    private func stream(messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.buildRequest(messages: messages)
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
                        try Task.checkCancellation()
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
            "messages": messages,
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
