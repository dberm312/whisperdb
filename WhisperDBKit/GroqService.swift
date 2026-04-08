import Foundation

public final class GroqService {
    private let apiKey: String
    private let baseURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    private let model = "whisper-large-v3-turbo"

    public init() throws {
        guard let key = EnvLoader.get("GROQ_API_KEY"), !key.isEmpty else {
            throw GroqError.missingAPIKey
        }
        self.apiKey = key
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        body.appendMultipart(boundary: boundary, name: "model", value: model)
        body.appendMultipart(boundary: boundary, name: "response_format", value: "text")
        body.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/mp4",
            data: audioData
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GroqError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw GroqError.emptyTranscription
        }

        return text
    }

    public enum GroqError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case emptyTranscription

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "GROQ_API_KEY not found. Create a .env file with GROQ_API_KEY=your_key"
            case .invalidResponse:
                return "Invalid response from Groq API"
            case .apiError(let code, let message):
                return "Groq API error (\(code)): \(message)"
            case .emptyTranscription:
                return "No speech detected in the audio"
            }
        }
    }
}
