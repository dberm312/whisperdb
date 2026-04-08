import Foundation
import SwiftUI

@MainActor
final class OrganizeViewModel: ObservableObject {
    let transcription: Transcription

    @Published var organizedText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?

    init(transcription: Transcription) {
        self.transcription = transcription
    }

    func startOrganizing() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        organizedText = ""

        Task {
            do {
                let service = try OpenRouterService()
                let stream = service.organize(text: transcription.text)

                for try await chunk in stream {
                    organizedText += chunk
                }
            } catch {
                self.error = error.localizedDescription
            }

            isLoading = false
        }
    }

    func copyToClipboard() {
        ClipboardService.copy(organizedText)
    }
}
