import Foundation

struct Transcription: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date

    var displayText: String {
        let maxLength = 80
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "…"
        }
        return text
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
