import SwiftUI
import WhisperDBKit

struct OrganizeView: View {
    @StateObject private var viewModel: OrganizeViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var chatFocused: Bool

    init(text: String) {
        _viewModel = StateObject(wrappedValue: OrganizeViewModel(text: text))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()

                IntensityTabBar(
                    selected: Binding(
                        get: { viewModel.session.selectedIntensity },
                        set: { viewModel.session.selectTab($0) }
                    ),
                    isLoading: { viewModel.session.isLoading($0) },
                    hasResult: { (viewModel.session.results[$0]?.isEmpty == false) },
                    onSelect: { viewModel.session.selectTab($0) }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                outputArea

                if !viewModel.session.currentOutput.isEmpty || viewModel.session.isRefining {
                    Divider()
                    chatRow
                }
            }
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.copyToClipboard()
                    } label: {
                        Label(
                            viewModel.copied ? "Copied!" : "Copy",
                            systemImage: viewModel.copied ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .disabled(viewModel.session.currentOutput.isEmpty)
                }
            }
        }
        .onAppear {
            if viewModel.session.results[viewModel.session.selectedIntensity] == nil {
                viewModel.session.selectTab(viewModel.session.selectedIntensity)
            }
        }
        .onDisappear {
            viewModel.session.cancelAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Original transcription")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(viewModel.originalText)
                .font(.callout)
                .lineLimit(3)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var outputArea: some View {
        let session = viewModel.session

        if let error = session.currentError {
            VStack(spacing: 12) {
                Spacer()
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Retry") {
                    session.generate(intensity: session.selectedIntensity)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.currentOutput.isEmpty && session.isLoadingCurrent {
            VStack {
                Spacer()
                ProgressView("Cleaning up (\(session.selectedIntensity.title))…")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.currentOutput.isEmpty {
            VStack {
                Spacer()
                Text("Select a cleanup level to begin.")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(.init(session.currentOutput))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            if session.isLoadingCurrent {
                HStack {
                    ProgressView().scaleEffect(0.6)
                    Text("Still streaming…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
    }

    private var chatRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let err = viewModel.session.refineError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .foregroundColor(.secondary)
                TextField("Ask for a change", text: Binding(
                    get: { viewModel.session.chatInstruction },
                    set: { viewModel.session.chatInstruction = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($chatFocused)
                .submitLabel(.send)
                .onSubmit { viewModel.session.submitChatInstruction() }
                .disabled(viewModel.session.isRefining)

                Button {
                    viewModel.session.submitChatInstruction()
                    chatFocused = false
                } label: {
                    if viewModel.session.isRefining {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                    }
                }
                .disabled(
                    viewModel.session.isRefining ||
                    viewModel.session.chatInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
    }
}
