import SwiftUI

// MARK: - Section Label

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(AppTheme.Colors.textTertiary)
    }
}

// MARK: - Health Score Ring

enum HealthStatus {
    case unknown
    case attention
    case good

    var label: String {
        switch self {
        case .unknown:   "Not scanned yet"
        case .attention: "Needs attention"
        case .good:      "Running great"
        }
    }

    var tint: Color {
        switch self {
        case .unknown:   AppTheme.Colors.textTertiary
        case .attention: FeatureAccent.boost.solid
        case .good:      FeatureAccent.cleanup.solid
        }
    }
}

struct HealthScoreRing: View {
    let progress: Double
    let status: HealthStatus
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Colors.border, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(progress, 0.0035))
                .stroke(status.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.86), value: progress)

            VStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(status.tint)

                Text(status.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 96)
            }
        }
    }

    private var statusSymbol: String {
        switch status {
        case .unknown:   "sparkles"
        case .attention: "exclamationmark.circle.fill"
        case .good:      "checkmark.circle.fill"
        }
    }
}

// MARK: - Feature Shortcut Card (dashboard grid item)

struct FeatureShortcutCard: View {
    let accent: FeatureAccent
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent.tint)
                        .frame(width: 46, height: 46)

                    Image(systemName: accent.symbolName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(accent.solid)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            }
        }
        .buttonStyle(.appInteractive)
        .cardHoverChrome(scale: 1.01)
    }
}

// MARK: - Stat Tile (small metric card)

struct StatTile: View {
    let accent: FeatureAccent
    let symbolName: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.tint)
                    .frame(width: 34, height: 34)

                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent.solid)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }
}

// MARK: - Accent Pill Badge

struct AccentPillBadge: View {
    let accent: FeatureAccent
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(accent.solid)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(accent.tint)
            }
    }
}
