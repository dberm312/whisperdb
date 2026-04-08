import Foundation
import SwiftUI
import WhisperDBKit

@MainActor
final class OrganizeViewModel: ObservableObject {
    let originalText: String

    @Published var organizedText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var copied = false

    private var organizeTask: Task<Void, Never>?

    init(text: String) {
        self.originalText = text
    }

    func startOrganizing() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        organizedText = ""

        organizeTask = Task {
            do {
                let service = try OpenRouterService()
                let stream = service.organize(text: originalText)

                for try await chunk in stream {
                    organizedText += chunk
                }
            } catch {
                self.error = error.localizedDescription
            }

            isLoading = false
        }
    }

    func cancelOrganizing() {
        organizeTask?.cancel()
        organizeTask = nil
    }

    func copyToClipboard() {
        UIPasteboard.general.string = organizedText
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
