import Foundation
import Network
import WhisperDBKit

final class RealtimeSessionServer {
    static let shared = RealtimeSessionServer()

    private let queue = DispatchQueue(label: "com.whisperdb.realtime-server")
    private var listener: NWListener?
    private var baseURL: URL?

    private init() {}

    func start() async throws -> URL {
        if let baseURL {
            return baseURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener

                let startContinuation = RealtimeStartContinuation(continuation)
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    switch state {
                    case .ready:
                        guard let port = listener?.port else {
                            startContinuation.resume(throwing: RealtimeServerError.missingPort)
                            return
                        }

                        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/")!
                        self?.baseURL = url
                        startContinuation.resume(returning: url)
                    case .failed(let error):
                        startContinuation.resume(throwing: error)
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)

        var buffer = Data()

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                [weak self] content, _, isComplete, error in
                guard let self else {
                    connection.cancel()
                    return
                }

                if let content {
                    buffer.append(content)
                }

                if let request = HTTPRequest(data: buffer) {
                    Task {
                        await self.respond(to: request, on: connection)
                    }
                    return
                }

                if error != nil || isComplete {
                    self.send(
                        status: 400,
                        contentType: "text/plain; charset=utf-8",
                        body: "Bad request",
                        on: connection
                    )
                    return
                }

                receiveMore()
            }
        }

        receiveMore()
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) async {
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            sendAsset(named: "index.html", on: connection)
        case ("GET", "/app.css"):
            sendAsset(named: "app.css", on: connection)
        case ("GET", "/app.js"):
            sendAsset(named: "app.js", on: connection)
        case ("POST", "/session"):
            await createRealtimeSession(from: request.body, on: connection)
        default:
            send(status: 404, contentType: "text/plain; charset=utf-8", body: "Not found", on: connection)
        }
    }

    private func createRealtimeSession(from sdp: Data, on connection: NWConnection) async {
        guard let apiKey = EnvLoader.get("OPENAI_API_KEY"), !apiKey.isEmpty else {
            send(
                status: 500,
                contentType: "text/plain; charset=utf-8",
                body: "OPENAI_API_KEY is not configured. Add it to .env or your process environment.",
                on: connection
            )
            return
        }

        guard let sdpText = String(data: sdp, encoding: .utf8), !sdpText.isEmpty else {
            send(status: 400, contentType: "text/plain; charset=utf-8", body: "Missing SDP body", on: connection)
            return
        }

        let sessionConfig = """
            {
              "type": "realtime",
              "model": "gpt-realtime-2",
              "output_modalities": ["text"],
              "audio": {
                "input": {
                  "transcription": {
                    "model": "gpt-realtime-whisper",
                    "language": "en"
                  },
                  "turn_detection": null
                }
              },
              "instructions": "Transcribe the user verbatim and quietly maintain a task list. Do not speak. Use the upsert_todo tool when the user says something actionable."
            }
            """

        let boundary = UUID().uuidString
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "sdp", value: sdpText)
        body.appendMultipart(boundary: boundary, name: "session", value: sessionConfig)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (responseBody, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                send(
                    status: 502,
                    contentType: "text/plain; charset=utf-8",
                    body: "Invalid OpenAI response",
                    on: connection
                )
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = String(data: responseBody, encoding: .utf8) ?? "Unknown OpenAI error"
                send(
                    status: httpResponse.statusCode,
                    contentType: "text/plain; charset=utf-8",
                    body: message,
                    on: connection
                )
                return
            }

            send(status: 201, contentType: "application/sdp", body: responseBody, on: connection)
        } catch {
            send(
                status: 502,
                contentType: "text/plain; charset=utf-8",
                body: "Failed to create Realtime session: \(error.localizedDescription)",
                on: connection
            )
        }
    }

    private func sendAsset(named name: String, on connection: NWConnection) {
        guard let data = loadRealtimeAsset(named: name) else {
            send(status: 404, contentType: "text/plain; charset=utf-8", body: "Asset not found", on: connection)
            return
        }

        send(status: 200, contentType: contentType(for: name), body: data, on: connection)
    }

    private func loadRealtimeAsset(named name: String) -> Data? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Realtime/\(name)"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/Realtime/\(name)"),
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources/Realtime"),
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Realtime"),
        ]

        for url in candidates.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }

        return nil
    }

    private func contentType(for filename: String) -> String {
        if filename.hasSuffix(".html") {
            return "text/html; charset=utf-8"
        }
        if filename.hasSuffix(".css") {
            return "text/css; charset=utf-8"
        }
        if filename.hasSuffix(".js") {
            return "application/javascript; charset=utf-8"
        }
        return "application/octet-stream"
    }

    private func send(status: Int, contentType: String, body: String, on connection: NWConnection) {
        send(status: status, contentType: contentType, body: Data(body.utf8), on: connection)
    }

    private func send(status: Int, contentType: String, body: Data, on connection: NWConnection) {
        let reason = HTTPReasonPhrase.phrase(for: status)
        var response = Data()
        response.append("HTTP/1.1 \(status) \(reason)\r\n".data(using: .utf8)!)
        response.append("Content-Type: \(contentType)\r\n".data(using: .utf8)!)
        response.append("Content-Length: \(body.count)\r\n".data(using: .utf8)!)
        response.append("Connection: close\r\n".data(using: .utf8)!)
        response.append("Cache-Control: no-store\r\n".data(using: .utf8)!)
        response.append("\r\n".data(using: .utf8)!)
        response.append(body)

        connection.send(
            content: response,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else { return nil }

        let headerEnd = headerRange.upperBound
        guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= headerEnd + contentLength else { return nil }

        method = String(requestParts[0]).uppercased()
        let rawPath = String(requestParts[1])
        path = rawPath.components(separatedBy: "?").first ?? rawPath
        body = Data(data[headerEnd..<(headerEnd + contentLength)])
    }
}

private enum HTTPReasonPhrase {
    static func phrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        default: return "OK"
        }
    }
}

private enum RealtimeServerError: LocalizedError {
    case missingPort

    var errorDescription: String? {
        switch self {
        case .missingPort:
            return "The local Realtime server did not receive a port."
        }
    }
}

private final class RealtimeStartContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(returning url: URL) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: url)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
