import AppKit
import SwiftUI

struct DuplicateRelatedGrid: View {
    let items: [CareScanDetailItem]
    let focusedID: String?
    @Binding var selectedIDs: Set<String>
    let onSelect: (CareScanDetailItem) -> Void

    private let tileWidth: CGFloat = 148
    private let tileHeight: CGFloat = 128
    private let columns = [
        GridItem(.fixed(148), spacing: 14),
        GridItem(.fixed(148), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(items) { item in
                    DuplicateSelectablePreview(
                        item: item,
                        isFocused: focusedID == item.id,
                        isChecked: selectedIDs.contains(item.id),
                        onSelect: { onSelect(item) },
                        onToggle: {
                            selectedIDs = [item.id]
                        }
                    )
                    .frame(width: tileWidth, height: tileHeight)
                }
            }
            .padding(.top, 14)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
        }
    }
}

struct DuplicateSelectablePreview: View {
    let item: CareScanDetailItem
    let isFocused: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                duplicatePreview
                    .frame(width: 148, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isFocused ? AppTheme.Colors.textPrimary : AppTheme.Colors.border,
                                lineWidth: isFocused ? 3 : 1
                            )
                    }
            }
            .buttonStyle(.plain)
            .cardHoverChrome(scale: 1.02)

            Button(action: onToggle) {
                DuplicateCheckbox(isChecked: isChecked)
            }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(8)
        }
        .frame(width: 148, height: 128)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var duplicatePreview: some View {
        if let image = NSImage(contentsOfFile: item.path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                AppTheme.Colors.glassBg
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
        }
    }
}

struct DuplicateCheckbox: View {
    let isChecked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isChecked ? FeatureAccent.clutter.gradient : LinearGradient(colors: [.black.opacity(0.48), .black.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 30, height: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isChecked ? AppTheme.Colors.border : .white.opacity(0.36), lineWidth: 2)
            }
            .overlay {
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                }
            }
            .shadow(color: .black.opacity(isChecked ? 0.18 : 0.1), radius: 4, x: 0, y: 2)
    }
}
