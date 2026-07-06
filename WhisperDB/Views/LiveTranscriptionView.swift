import SwiftUI
import WhisperDBKit

/// Live-caption style view: committed text in full strength, the current interim
/// hypothesis dimmed, auto-scrolling as new words arrive.
///
/// The content lays out at its natural height inside a single scroll view; the view
/// reports that natural height to its window controller so the panel can auto-fit. The
/// scroll view only scrolls once the panel is capped (or manually shrunk) below it.
struct LiveTranscriptionView: View {
    @ObservedObject var manager: TranscriptionManager
    /// Reports the natural height the panel needs to show everything (content + chrome).
    let onContentHeightChange: (CGFloat) -> Void

    /// Outer padding around the rounded card, added on top of the measured content.
    private let outerPadding: CGFloat = 8

    init(manager: TranscriptionManager, onContentHeightChange: @escaping (CGFloat) -> Void) {
        self.manager = manager
        self.onContentHeightChange = onContentHeightChange
    }

    private var hasText: Bool {
        !manager.liveText.isEmpty || !manager.partialText.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ContentHeightKey.self,
                                value: geo.size.height + outerPadding * 2
                            )
                        }
                    )
                    .id("content")
            }
            .onChange(of: manager.displayedTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("content", anchor: .bottom)
                }
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                onContentHeightChange(height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(outerPadding)
    }

    /// The card content at its natural height (header + transcript + summary).
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Group {
                if hasText {
                    transcriptText
                } else {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showSummary {
                summarySection
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.state == .recording ? Color.red : Color.secondary)
                .frame(width: 9, height: 9)
            Text(headerTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var showSummary: Bool {
        !manager.summaryText.isEmpty || (manager.state == .recording && hasText)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 8) {
                Picker("Summary level", selection: $manager.summaryLevel) {
                    ForEach(SummaryLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 240)

                summaryStatusIndicator
                Spacer()
            }
            .foregroundStyle(.secondary)

            Group {
                if !manager.summaryText.isEmpty {
                    MarkdownText(markdown: manager.summaryText)
                } else if let placeholder = summaryPlaceholder {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Small status next to the "Summary" label: waiting for a pause, or loading. Lives
    /// in the header (not the body) so an existing summary stays visible while refreshing.
    @ViewBuilder
    private var summaryStatusIndicator: some View {
        switch manager.summaryStatus {
        case .waiting:
            Text("waiting for a pause…")
                .font(.system(size: 11))
                .italic()
        case .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading…")
                    .font(.system(size: 11))
            }
        case .idle, .ready:
            EmptyView()
        }
    }

    /// Body placeholder shown only when there is no summary yet.
    private var summaryPlaceholder: String? {
        switch manager.summaryStatus {
        case .waiting, .idle: return "Will organize once you pause…"
        case .loading: return "Loading…"
        case .ready: return nil
        }
    }

    private var transcriptText: some View {
        // Committed text plus the dimmed interim hypothesis, as one flowing block.
        (Text(manager.liveText)
            .foregroundStyle(.primary)
            + Text(manager.liveText.isEmpty || manager.partialText.isEmpty ? "" : " ")
            + Text(manager.partialText)
            .foregroundStyle(.secondary))
            .font(.system(size: 20, weight: .regular))
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
    }

    private var headerTitle: String {
        switch manager.state {
        case .recording: return "Listening…"
        case .processing: return "Finishing up…"
        case .reviewing: return "Copied — tap ⌥ to dismiss"
        case .idle: return "Done"
        }
    }

    private var placeholder: String {
        manager.state == .processing ? "Transcribing…" : "Start speaking…"
    }
}

/// Reports the natural height of the panel content up to the window controller.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Renders a small subset of block markdown (headings, bullet and numbered lists,
/// paragraphs) since SwiftUI's `Text(.init(markdown:))` only parses inline markup.
private struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(for: line)
            }
        }
        .textSelection(.enabled)
    }

    private var lines: [String] {
        markdown.components(separatedBy: .newlines)
    }

    @ViewBuilder
    private func row(for rawLine: String) -> some View {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if line.isEmpty {
            Spacer().frame(height: 4)
        } else if let heading = headingContent(line) {
            inlineText(heading)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 2)
        } else if let bullet = bulletContent(line) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                inlineText(bullet)
            }
            .font(.system(size: 13))
        } else if let (number, rest) = orderedContent(line) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).")
                    .fontWeight(.medium)
                inlineText(rest)
            }
            .font(.system(size: 13))
        } else {
            inlineText(line)
                .font(.system(size: 13))
        }
    }

    /// Inline emphasis (bold/italic/code) via AttributedString, falling back to plain text.
    private func inlineText(_ string: String) -> Text {
        if let attributed = try? AttributedString(markdown: string) {
            return Text(attributed)
        }
        return Text(string)
    }

    private func headingContent(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let stripped = line.drop(while: { $0 == "#" })
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    private func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func orderedContent(_ line: String) -> (Int, String)? {
        // Matches "1. text" / "12) text".
        let scanner = Scanner(string: line)
        guard let number = scanner.scanInt() else { return nil }
        guard scanner.scanString(".") != nil || scanner.scanString(")") != nil else { return nil }
        let rest = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (number, rest)
    }
}
