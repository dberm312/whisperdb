import SwiftUI

struct HistoryView: View {
    @ObservedObject var manager: TranscriptionManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dictation History")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if !manager.history.isEmpty {
                    Button("Clear All") {
                        manager.clearHistory()
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Transcription list
            if manager.history.isEmpty {
                VStack {
                    Spacer()
                    Text("No transcriptions yet")
                        .foregroundColor(.secondary)
                        .font(.title3)
                    Text("Press ⌥ Space to start recording")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.callout)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.history) { transcription in
                        HistoryRow(transcription: transcription) {
                            manager.copyFromHistory(transcription)
                        } onOrganize: {
                            OrganizeWindowController.shared.openWindow(for: transcription)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct HistoryRow: View {
    let transcription: Transcription
    let onCopy: () -> Void
    let onOrganize: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transcription.text)
                .textSelection(.enabled)
                .lineLimit(4)

            HStack {
                Text(transcription.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(copied ? "Copied" : "Copy") {
                    onCopy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }
                .controlSize(.small)

                Button("Organize") {
                    onOrganize()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
