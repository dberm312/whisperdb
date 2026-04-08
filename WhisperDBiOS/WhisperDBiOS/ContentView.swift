import SwiftUI
import WhisperDBKit

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel
    @State private var showOrganize = false
    @State private var organizeText = ""
    @State private var expandedItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WhisperDB")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // History or empty state
            if viewModel.history.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No recording history")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.history) { item in
                        HistoryRow(
                            item: item,
                            isExpanded: expandedItemID == item.id,
                            onTap: {
                                withAnimation {
                                    expandedItemID = expandedItemID == item.id ? nil : item.id
                                }
                            },
                            onCopy: {
                                UIPasteboard.general.string = item.text
                                viewModel.showCopied()
                            },
                            onOrganize: {
                                organizeText = item.text
                                showOrganize = true
                            }
                        )
                    }
                    .onDelete { offsets in
                        viewModel.deleteHistoryItem(at: offsets)
                    }
                }
                .listStyle(.plain)
            }

            // Error display
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }

            Divider()

            // Recording bar at bottom
            RecordingBar(viewModel: viewModel)
        }
        .alert("Recording Limit", isPresented: $viewModel.showLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Recording stopped at 15 minutes to prevent accidental over-recording.")
        }
        .sheet(isPresented: $showOrganize) {
            OrganizeView(text: organizeText)
        }
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let item: RecordingViewModel.HistoryItem
    let isExpanded: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onOrganize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .lineLimit(isExpanded ? nil : 3)
                .font(.body)
                .textSelection(.enabled)

            HStack {
                Text(item.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isExpanded {
                    Spacer()
                    Button {
                        onCopy()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        onOrganize()
                    } label: {
                        Label("Organize", systemImage: "text.justify.left")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Recording Bar

struct RecordingBar: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Mic button
            Button {
                viewModel.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 56, height: 56)
                        .scaleEffect(viewModel.isRecording ? 1.0 + CGFloat(viewModel.audioLevel) * 0.12 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: viewModel.audioLevel)

                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)

            // Status
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.isRecording {
                    Text(viewModel.formattedElapsedTime)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.red)
                    Text("of \(viewModel.formattedMaxDuration)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Tap to record")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }
}
