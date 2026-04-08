import SwiftUI

struct OrganizeView: View {
    @StateObject private var viewModel: OrganizeViewModel
    @Environment(\.dismiss) private var dismiss

    init(text: String) {
        _viewModel = StateObject(wrappedValue: OrganizeViewModel(text: text))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Original text preview
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

                if viewModel.isLoading && !viewModel.organizedText.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Still organizing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
                        Label(viewModel.copied ? "Copied!" : "Copy", systemImage: viewModel.copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(viewModel.organizedText.isEmpty)
                }
            }
        }
        .onAppear {
            viewModel.startOrganizing()
        }
        .onDisappear {
            viewModel.cancelOrganizing()
        }
    }
}
