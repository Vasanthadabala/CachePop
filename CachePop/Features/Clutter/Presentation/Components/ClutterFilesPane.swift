import SwiftUI

struct ClutterFilesPane: View {
    let section: ClutterSection
    let items: [CareScanDetailItem]
    let permissions: [String]
    let duplicateCounts: [String: Int]
    @Binding var selectedItemID: String?
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.94))
                .padding(.bottom, 12)

            Text(section.description)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.56))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            HStack(spacing: 6) {
                Text("Show:")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))

                Text("All Files")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(.bottom, 30)

            if isScanning {
                ClutterEmptyState(title: "Scanning files...", subtitle: "Checking large files and comparing duplicate file contents.")
            } else if items.isEmpty {
                ClutterEmptyState(title: "Nothing found", subtitle: section.emptyMessage)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                selectedItemID = item.id
                            } label: {
                                ClutterFileRow(
                                    item: item,
                                    section: section,
                                    duplicateTotal: section == .duplicates ? duplicateCounts[item.id, default: 2] : nil,
                                    isSelected: selectedItemID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }

            if !permissions.isEmpty {
                Text(permissions[0])
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.46))
                    .lineLimit(3)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

}

struct ClutterEmptyState: View {
    let title: String
    let subtitle: String

    private var isScanning: Bool { title.hasPrefix("Scanning") }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.glassBg)
                    .frame(width: 50, height: 50)

                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.86))

                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.glassBg.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
        }
    }
}

struct ClutterFileRow: View {
    let item: CareScanDetailItem
    let section: ClutterSection
    let duplicateTotal: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ClutterFileIcon(item: item, section: section)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                    .lineLimit(1)

                Text(item.formattedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.5))
            }

            Spacer()

            if let duplicateTotal {
                Text("\(duplicateTotal)")
                    .foregroundStyle(.white)
                    .frame(minWidth: 42, minHeight: 28)
                    .background(FeatureAccent.clutter.solid)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: section.symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FeatureAccent.clutter.tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FeatureAccent.clutter.solid.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .rowHoverHighlight()
    }
}

struct ClutterFileIcon: View {
    let item: CareScanDetailItem
    let section: ClutterSection

    var body: some View {
        ZStack {
            if let image = NSImage(contentsOfFile: item.path), section == .duplicates {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FeatureAccent.clutter.gradient)

                Image(systemName: section.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
