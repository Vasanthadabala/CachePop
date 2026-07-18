import AppKit
import SwiftUI

struct ClutterSummaryTallCard: View {
    let title: String
    let subtitle: String
    let fileCount: Int
    let sizeText: String
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(fileCount == 0 ? subtitle : "Remove \(sizeText) of duplicate files.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.72))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(alignment: .bottom) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.78))
                    .offset(y: -12)

                Image(systemName: "doc.fill")
                    .font(.system(size: 94, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.95))
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 7)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.84))
                    .offset(y: -8)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            HStack {
                Spacer()
                ClutterSummaryReviewButton(onReview: onReview)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .background(summaryCardBackground)
    }
}

struct ClutterSummaryWideCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let imageItems: [CareScanDetailItem]
    let onReview: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.72))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing) {
                ClutterSummaryPreviewStrip(symbolName: symbolName, items: imageItems)

                Spacer()

                ClutterSummaryReviewButton(onReview: onReview)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(summaryCardBackground)
    }
}

struct ClutterSummaryPreviewStrip: View {
    let symbolName: String
    let items: [CareScanDetailItem]

    var body: some View {
        HStack(spacing: 14) {
            if items.isEmpty {
                Image(systemName: symbolName)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.72))
                    .frame(width: 52, height: 52)
            } else {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    summaryPreview(for: item)
                        .frame(width: 48, height: 58)
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5)
                        .offset(y: CGFloat(index % 2) * 4)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryPreview(for item: CareScanDetailItem) -> some View {
        if let image = NSImage(contentsOfFile: item.path), ClutterScanResult.isImagePath(item.path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.9))
                .overlay {
                    Image(systemName: item.kind == "Large File" ? "doc.fill" : "doc.on.doc.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
        }
    }
}

struct ClutterSummaryReviewButton: View {
    let onReview: () -> Void

    var body: some View {
        Button("Review", action: onReview)
            .buttonStyle(.appInteractive)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.inverseText)
            .frame(width: 84, height: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FeatureAccent.clutter.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }
            }
            .raisedButtonChrome(cornerRadius: 10)
    }
}

var summaryCardBackground: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(FeatureAccent.clutter.gradient)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
}
