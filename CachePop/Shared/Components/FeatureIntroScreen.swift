import SwiftUI

struct FeatureIntroPoint: Identifiable {
    let symbolName: String
    let title: String
    let subtitle: String

    var id: String { title }
}

/// The scan scope is one reading surface, with related details side by side.
struct FeatureIntroScreen<Header: View>: View {
    let points: [FeatureIntroPoint]
    let pointsTitle: String
    @ViewBuilder var header: Header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                header
                VStack(alignment: .leading, spacing: 9) {
                    Text(pointsTitle)
                        .font(AppTheme.Typography.title2)
                        .accessibilityAddTraits(.isHeader)
                    Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 0) {
                        ForEach(0..<((points.count + 1) / 2), id: \.self) { row in
                            if row > 0 {
                                RowDivider(leadingInset: 0)
                                    .gridCellColumns(2)
                                    .gridCellUnsizedAxes(.horizontal)
                            }
                            GridRow {
                                FeatureIntroPointView(point: points[row * 2])
                                if row * 2 + 1 < points.count {
                                    FeatureIntroPointView(point: points[row * 2 + 1])
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .card()
                }
            }
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureIntroPointView: View {
    let point: FeatureIntroPoint

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(symbolName: point.symbolName, size: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(point.title).font(AppTheme.Typography.headline)
                Text(point.subtitle)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// One action per scan. Storage pages use the instrument at the right for a live capacity reading.
struct FeatureIntroHeader<Actions: View>: View {
    let section: AppSection
    var caption: String?
    let title: String
    var unit: String?
    let detail: String
    var disk: DiskInfo?
    @ViewBuilder var actions: Actions

    var body: some View {
        let tint = AppTheme.Colors.textSecondary
        HStack(spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 6) {
                if let caption {
                    Text(caption)
                        .font(AppTheme.Typography.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(title)
                        .font(.system(size: unit == nil ? 30 : 42, weight: .semibold))
                        .tracking(-1)
                        .monospacedDigit()
                    if let unit {
                        Text(unit)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let disk, disk.totalBytes > 0 {
                StorageDial(disk: disk)
            } else {
                ZStack {
                    let plate = RoundedRectangle(cornerRadius: 19, style: .continuous)
                    plate.fill(tint.opacity(0.10)).rotationEffect(.degrees(-12)).offset(x: -7, y: -3)
                    plate.fill(AppTheme.Colors.card)
                    plate.fill(tint.opacity(0.12).gradient)
                        .overlay(plate.strokeBorder(tint.opacity(0.19)))
                    Image(systemName: section.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(tint)
                }
                .frame(width: 70, height: 70)
                .padding(.horizontal, 15)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .card()
    }
}

private struct StorageDial: View {
    let disk: DiskInfo

    var body: some View {
        let fraction = disk.usedFraction
        let percent = Int((fraction * 100).rounded())
        let color = disk.isLow ? AppTheme.Status.warning : AppTheme.Colors.accent
        ZStack {
            Circle().strokeBorder(color.opacity(0.25), style: StrokeStyle(lineWidth: 3, dash: [1, 5]))
            Circle().stroke(AppTheme.Colors.track, lineWidth: 7).padding(9)
            Circle().trim(from: 0, to: fraction)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(9)
            VStack(spacing: 0) {
                Text("\(percent)%").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("used").font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(width: 100, height: 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent of disk space used")
    }
}
