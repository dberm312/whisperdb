import Foundation
import SwiftUI
import UIKit
import WhisperDBKit

@MainActor
final class OrganizeViewModel: ObservableObject {
    let session: OrganizeSession

    @Published var copied = false

    init(text: String) {
        self.session = OrganizeSession(originalText: text)
    }

    var originalText: String { session.originalText }

    func copyToClipboard() {
        UIPasteboard.general.string = session.currentOutput
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
