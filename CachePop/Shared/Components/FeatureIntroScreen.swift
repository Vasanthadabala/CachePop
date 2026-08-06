import SwiftUI

/// One capability listed on a feature's landing screen.
struct FeatureIntroPoint: Identifiable {
    let id = UUID()
    let symbolName: String
    let title: String
    let subtitle: String

    init(symbolName: String, title: String, subtitle: String) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
    }
}

/// The shared landing screen shown when a user opens a feature from the sidebar.
///
/// Every feature uses this same layout so moving between them feels like one app: a hero
/// glyph, the feature name, a one-line explanation, the list of what it covers, and a single
/// primary action. Anything feature-specific goes in `accessory` (e.g. Clutter's folder picker).
struct FeatureIntroScreen<Accessory: View>: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let points: [FeatureIntroPoint]
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder var accessory: Accessory

    init(
        symbolName: String,
        title: String,
        subtitle: String,
        points: [FeatureIntroPoint],
        actionTitle: String = "Scan",
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        self.points = points
        self.actionTitle = actionTitle
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 36)

                FeatureIntroGlyph(symbolName: symbolName)
                    .padding(.bottom, 26)

                Text(title)
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.bottom, 10)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
                    .padding(.bottom, 30)

                if !points.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            FeatureIntroPointRow(point: point)

                            if index < points.count - 1 {
                                Divider()
                                    .overlay(AppTheme.Colors.border)
                                    .padding(.leading, 62)
                            }
                        }
                    }
                    .frame(maxWidth: 440)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.Colors.border, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
                    }
                    .padding(.bottom, 26)
                }

                accessory

                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.appInteractive)
                    .padding(.horizontal, 40)
                    .frame(height: 46)
                    .background {
                        Capsule(style: .continuous)
                            .fill(FeatureAccent.dashboard.gradient)
                    }
                    .accentGlow(.dashboard, radius: 16, y: 6)
                    .padding(.top, 4)

                Spacer(minLength: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.99)))
    }
}

/// Large rounded-square hero glyph, tinted in the app's single accent blue.
struct FeatureIntroGlyph: View {
    let symbolName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(FeatureAccent.dashboard.tint)
                .frame(width: 108, height: 108)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FeatureAccent.dashboard.gradient)
                .frame(width: 78, height: 78)
                .accentGlow(.dashboard, radius: 18, y: 8)

            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct FeatureIntroPointRow: View {
    let point: FeatureIntroPoint

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FeatureAccent.dashboard.tint)
                    .frame(width: 32, height: 32)

                Image(systemName: point.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FeatureAccent.dashboard.solid)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(point.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(point.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }
}

/// Shared circular progress button used by the scanning screens (Stop / percentage).
struct ScanProgressButton: View {
    let title: String
    let progress: Double?
    var isSpinning = false
    let action: () -> Void

    @State private var rotation = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(FeatureAccent.dashboard.gradient)
                    .accentGlow(.dashboard, radius: 22, y: 8)

                if let progress {
                    Circle()
                        .trim(from: 0, to: max(progress, 0.01))
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(6)
                } else if isSpinning {
                    Circle()
                        .trim(from: 0.08, to: 0.88)
                        .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(rotation ? 360 : 0))
                        .padding(6)
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotation)
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .contentShape(Circle())
        }
        .buttonStyle(.appInteractive)
        .onAppear { rotation = true }
    }
}
