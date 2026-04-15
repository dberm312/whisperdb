import SwiftUI
import WhisperDBKit

struct OrganizeView: View {
    @StateObject var viewModel: OrganizeViewModel
    @FocusState private var chatFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            tabBar
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            outputArea

            if !viewModel.session.currentOutput.isEmpty || viewModel.session.isRefining {
                Divider()
                chatRow
            }

            Divider()

            bottomBar
        }
        .frame(minWidth: 560, minHeight: 460)
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
            Text(viewModel.transcription.text)
                .font(.callout)
                .lineLimit(3)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var tabBar: some View {
        IntensityTabBar(
            selected: Binding(
                get: { viewModel.session.selectedIntensity },
                set: { viewModel.session.selectTab($0) }
            ),
            isLoading: { viewModel.session.isLoading($0) },
            hasResult: { (viewModel.session.results[$0]?.isEmpty == false) },
            onSelect: { viewModel.session.selectTab($0) }
        )
    }

    @ViewBuilder
    private var outputArea: some View {
        let session = viewModel.session

        if let error = session.currentError {
            VStack {
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
                TextField("Ask for a change — e.g. \"make it shorter\"", text: Binding(
                    get: { viewModel.session.chatInstruction },
                    set: { viewModel.session.chatInstruction = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($chatFocused)
                .onSubmit { viewModel.session.submitChatInstruction() }
                .disabled(viewModel.session.isRefining)

                Button {
                    viewModel.session.submitChatInstruction()
                } label: {
                    if viewModel.session.isRefining {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.session.isRefining ||
                    viewModel.session.chatInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    private var bottomBar: some View {
        HStack {
            if viewModel.session.isLoadingCurrent && !viewModel.session.currentOutput.isEmpty {
                ProgressView().scaleEffect(0.6)
                Text("Streaming…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Copy") {
                viewModel.copyToClipboard()
            }
            .disabled(viewModel.session.currentOutput.isEmpty)
            .keyboardShortcut("c", modifiers: .command)
        }
        .padding(12)
    }
}
