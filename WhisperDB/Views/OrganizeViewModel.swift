import Foundation
import SwiftUI
import WhisperDBKit

@MainActor
final class OrganizeViewModel: ObservableObject {
    let transcription: Transcription
    let session: OrganizeSession

    init(transcription: Transcription) {
        self.transcription = transcription
        self.session = OrganizeSession(originalText: transcription.text)
    }

    func copyToClipboard() {
        ClipboardService.copy(session.currentOutput)
    }
}
