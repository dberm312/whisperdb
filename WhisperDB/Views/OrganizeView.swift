import SwiftUI

struct OrganizeView: View {
    @StateObject var viewModel: OrganizeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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

            Divider()

            // Organized output
            if let error = viewModel.error {
                VStack {
                    Spacer()
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.organizedText.isEmpty && viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Organizing with Opus...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(.init(viewModel.organizedText))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

            Divider()

            // Bottom bar
            HStack {
                if viewModel.isLoading && !viewModel.organizedText.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Spacer()

                Button("Copy") {
                    viewModel.copyToClipboard()
                }
                .disabled(viewModel.organizedText.isEmpty)
                .keyboardShortcut("c", modifiers: .command)
            }
            .padding(12)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            viewModel.startOrganizing()
        }
    }
}
