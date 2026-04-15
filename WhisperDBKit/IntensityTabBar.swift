import SwiftUI

public struct IntensityTabBar: View {
    @Binding var selected: CleanupIntensity
    let isLoading: (CleanupIntensity) -> Bool
    let hasResult: (CleanupIntensity) -> Bool
    let onSelect: (CleanupIntensity) -> Void

    public init(
        selected: Binding<CleanupIntensity>,
        isLoading: @escaping (CleanupIntensity) -> Bool,
        hasResult: @escaping (CleanupIntensity) -> Bool,
        onSelect: @escaping (CleanupIntensity) -> Void
    ) {
        self._selected = selected
        self.isLoading = isLoading
        self.hasResult = hasResult
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(CleanupIntensity.allCases) { intensity in
                tab(for: intensity)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func tab(for intensity: CleanupIntensity) -> some View {
        let isSelected = selected == intensity
        let loading = isLoading(intensity)
        let generated = hasResult(intensity)

        Button {
            onSelect(intensity)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: intensity.systemSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(loading ? 0 : 1)
                    if loading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 18, height: 18)

                Text(intensity.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                if generated && !isSelected && !loading {
                    Circle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.75))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(intensity.subtitle)
    }
}
