import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct RecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var isRecording: Bool
    }

    var maxDurationSeconds: Int
}
