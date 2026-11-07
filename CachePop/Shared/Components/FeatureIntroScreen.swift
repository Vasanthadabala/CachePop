import SwiftUI

/// One thing a feature looks at, listed on its start screen.
struct FeatureIntroPoint: Identifiable {
    let symbolName: String
    let title: String
    let subtitle: String
    /// Only when the point is one of the categories the feature colours later (Clean Up).
    var hue: Hue?

    var id: String { title }
}

/// The start screen every feature shares: the section's tape header (with its one primary
/// action), then what the feature covers.
struct FeatureIntroScreen<Header: View>: View {
    var points: [FeatureIntroPoint] = []
    var pointsTitle = "What it covers"
    @ViewBuilder var header: Header

    init(points: [FeatureIntroPoint] = [], pointsTitle: String = "What it covers", @ViewBuilder header: () -> Header) {
        self.points = points
        self.pointsTitle = pointsTitle
        self.header = header()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
                header
                    .revealOnAppear(0)

                if !points.isEmpty {
                    Text(pointsTitle)
                        .font(AppTheme.Typography.title2)
                        .revealOnAppear(1)
                        .padding(.top, AppTheme.Spacing.xs)
                        .padding(.horizontal, AppTheme.Spacing.xxs)

                    // Two per row; cards in a row share its height so the grid stays even.
                    Grid(horizontalSpacing: AppTheme.Spacing.s, verticalSpacing: AppTheme.Spacing.s) {
                        ForEach(0..<((points.count + 1) / 2), id: \.self) { row in
                            GridRow {
                                FeatureIntroPointView(point: points[row * 2])
                                    .revealOnAppear(2 + row * 2)
                                if row * 2 + 1 < points.count {
                                    FeatureIntroPointView(point: points[row * 2 + 1])
                                        .revealOnAppear(3 + row * 2)
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.l)
        }
    }
}

/// The disk as a measuring tape: used in the accent (orange when space is low), free left open.
func diskTape(_ disk: DiskInfo) -> Tape {
    Tape(
        segments: [Tape.Segment(from: 0, to: disk.usedFraction, color: disk.isLow ? AppTheme.Status.warning : AppTheme.Colors.accent)],
        leading: "0",
        center: "\(ByteSize.string(disk.usedBytes)) used",
        trailing: ByteSize.string(disk.totalBytes)
    )
}

private struct FeatureIntroPointView: View {
    let point: FeatureIntroPoint

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.s + 2) {
            IconTile(symbolName: point.symbolName, size: 30, hue: point.hue)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.title)
                    .font(AppTheme.Typography.headline)
                Text(point.subtitle)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}
