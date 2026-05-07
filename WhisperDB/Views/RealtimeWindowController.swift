import AppKit
import WebKit

@MainActor
final class RealtimeWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate,
    WKScriptMessageHandler, WKUIDelegate
{
    static let shared = RealtimeWindowController()

    private let server = RealtimeSessionServer.shared
    private weak var manager: TranscriptionManager?
    private var window: NSPanel?
    private var webView: WKWebView?
    private var isStoppingFromWindowClose = false

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed]
            ),
            let json = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return json
    }

    var hasOpenWindow: Bool {
        window?.isVisible == true
    }

    func focusWindow() {
        guard let window, window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func startRecording(with manager: TranscriptionManager) {
        self.manager = manager
        openWindowIfNeeded()

        Task { @MainActor in
            do {
                let baseURL = try await server.start()
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "autostart", value: "1"),
                    URLQueryItem(name: "session", value: UUID().uuidString),
                ]

                guard let url = components.url else {
                    manager.failRealtimeRecording(message: "Failed to build local Realtime URL.")
                    return
                }

                webView?.load(URLRequest(url: url))
            } catch {
                manager.failRealtimeRecording(
                    message: "Failed to start local Realtime server: \(error.localizedDescription)"
                )
            }
        }
    }

    func stopRecording() {
        guard let webView else {
            manager?.completeRealtimeRecording(transcript: "")
            return
        }

        let script = "window.stopRealtimeFromNative && window.stopRealtimeFromNative();"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.manager?.completeRealtimeRecording(
                        transcript: "",
                        error: "Failed to stop Realtime session: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func openWindowIfNeeded() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "realtime")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        self.webView = webView

        let panel = NSPanel(
            contentRect: initialWindowFrame(),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "WhisperDB Live"
        panel.contentView = webView
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 320)
        panel.setFrameAutosaveName("WhisperDBRealtimePanel")

        window = panel

        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func initialWindowFrame() -> NSRect {
        let size = NSSize(width: 360, height: 360)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.maxY - size.height - margin
        )
        return NSRect(origin: origin, size: size)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if manager?.state == .recording {
            isStoppingFromWindowClose = true
            stopRecording()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil

        if isStoppingFromWindowClose {
            isStoppingFromWindowClose = false
        }

        if OrganizeWindowController.shared.hasOpenWindows == false {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "realtime", let body = message.body as? [String: Any],
            let type = body["type"] as? String
        else {
            return
        }

        switch type {
        case "sessionStarted":
            manager?.realtimeDidStart()
        case "sessionStopped":
            let transcript = body["transcript"] as? String ?? ""
            manager?.completeRealtimeRecording(transcript: transcript)
        case "startRequested":
            if manager?.state == .idle {
                manager?.toggle()
            }
        case "error":
            let errorMessage = body["message"] as? String ?? "Realtime session failed."
            manager?.failRealtimeRecording(message: errorMessage)
        case "copyText", "copyTodos":
            let text = body["text"] as? String ?? ""
            let copyID = body["copyId"] as? String ?? "todos"
            let copyIDLiteral = Self.javascriptStringLiteral(copyID)
            ClipboardService.copy(text)
            webView?.evaluateJavaScript(
                "window.realtimeCopyAcknowledged && window.realtimeCopyAcknowledged(\(copyIDLiteral));"
            )
        default:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }
}
