import AppKit
import Foundation
import IOKit
import os

protocol MediaPlaybackBackend: Sendable {
    func isNowPlaying() async -> Bool?
    @discardableResult
    func togglePlayback() -> Bool
}

@MainActor
final class MediaPlaybackController {
    private let backend: any MediaPlaybackBackend
    private let logger = Logger(subsystem: "com.whisperdb.app", category: "media-playback")
    private var shouldResumeAfterRecording = false
    private var pauseTask: Task<Void, Never>?

    init(backend: any MediaPlaybackBackend = SystemMediaPlaybackBackend()) {
        self.backend = backend
    }

    func handleRecordingDidStart() {
        shouldResumeAfterRecording = false

        let backend = self.backend
        pauseTask = Task {
            guard let isPlaying = await backend.isNowPlaying() else {
                logger.debug("Skipping media pause because playback state could not be determined")
                return
            }

            guard isPlaying else {
                logger.debug("Media was not playing when recording started")
                return
            }

            guard backend.togglePlayback() else {
                logger.warning("Failed to pause media when recording started")
                return
            }

            shouldResumeAfterRecording = true
        }
    }

    func handleRecordingDidStop() {
        defer { shouldResumeAfterRecording = false }

        guard shouldResumeAfterRecording else { return }

        if !backend.togglePlayback() {
            logger.warning("Failed to resume media after recording stopped")
        }
    }
}

final class SystemMediaPlaybackBackend: MediaPlaybackBackend, @unchecked Sendable {
    private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
    private typealias GetNowPlayingApplicationIsPlaying = @convention(c) (DispatchQueue, IsPlayingCallback) -> Void

    private let logger = Logger(subsystem: "com.whisperdb.app", category: "media-playback")
    private let queryQueue = DispatchQueue(label: "com.whisperdb.media-playback")
    private let getNowPlayingApplicationIsPlaying: GetNowPlayingApplicationIsPlaying?
    private let mediaRemoteHandle: UnsafeMutableRawPointer?

    init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/Versions/A/MediaRemote"
        let handle = dlopen(frameworkPath, RTLD_LAZY)
        mediaRemoteHandle = handle

        if let handle {
            getNowPlayingApplicationIsPlaying = "MRMediaRemoteGetNowPlayingApplicationIsPlaying".withCString { symbolName in
                guard let symbol = dlsym(handle, symbolName) else { return nil }
                return unsafeBitCast(symbol, to: GetNowPlayingApplicationIsPlaying.self)
            }
        } else {
            getNowPlayingApplicationIsPlaying = nil
            if let error = dlerror() {
                logger.error("Failed to load MediaRemote: \(String(cString: error), privacy: .public)")
            } else {
                logger.error("Failed to load MediaRemote")
            }
        }
    }

    deinit {
        if let mediaRemoteHandle {
            dlclose(mediaRemoteHandle)
        }
    }

    func isNowPlaying() async -> Bool? {
        guard let getNowPlayingApplicationIsPlaying else { return nil }

        return await withCheckedContinuation { continuation in
            let callback: IsPlayingCallback = { playing in
                continuation.resume(returning: playing)
            }
            getNowPlayingApplicationIsPlaying(queryQueue, callback)
        }
    }

    @discardableResult
    func togglePlayback() -> Bool {
        guard ClipboardService.ensureAccessibilityPermission(prompt: false) else {
            logger.warning("Skipping media toggle because Accessibility permission is not granted")
            return false
        }

        return postPlayPauseEvent(isKeyDown: true) && postPlayPauseEvent(isKeyDown: false)
    }

    private func postPlayPauseEvent(isKeyDown: Bool) -> Bool {
        let flagBits = isKeyDown ? 0xA00 : 0xB00
        let data1 = (Int(NX_KEYTYPE_PLAY) << 16) | flagBits

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flagBits)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            logger.error("Failed to create play/pause media key event")
            return false
        }

        event.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    }
}
