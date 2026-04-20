import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            // Lock screen presentation
            RecordingLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Recording")
                            .font(.headline)
                        Text(
                            "\(formatTime(context.state.elapsedSeconds)) / \(formatTime(context.attributes.maxDurationSeconds))"
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: URL(string: "whisperdb://stop")!) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
            }
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@available(iOS 16.1, *)
struct RecordingLockScreenView: View {
    let context: ActivityViewContext<RecordingAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("WhisperDB Recording")
                    .font(.headline)
                Text(
                    "\(formatTime(context.state.elapsedSeconds)) / \(formatTime(context.attributes.maxDurationSeconds))"
                )
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            }

            Spacer()

            Link(destination: URL(string: "whisperdb://stop")!) {
                Image(systemName: "stop.circle.fill")
                    .foregroundColor(.red)
                    .font(.title)
            }
        }
        .padding()
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
