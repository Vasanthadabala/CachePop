import SwiftUI

struct CareScanningContent: View {
    let scanProgress: Double
    let snapshot: CareScanSnapshot
    let pulse: Bool
    let onStop: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = min(max(width / 930, 0.82), 1.04)
            let contentWidth = max(width - 56, 620)
            let activeSection = ActiveScanSection(progress: scanProgress)
            let topActive = ActiveScanSection.topSections.contains(activeSection)
            let bottomActive = ActiveScanSection.bottomSections.contains(activeSection)
            let topRowHeight = (topActive ? 252 : 156) * scale
            let bottomRowHeight = (bottomActive ? 268 : 172) * scale

            VStack(spacing: 0) {
                ScanningTopBar()

                VStack(spacing: 18 * scale) {
                    VStack(spacing: 7 * scale) {
                        Text(activeSection.headline)
                            .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Care.heading)
                            .contentTransition(.opacity)

                        Text(snapshot.currentDetail.isEmpty ? activeSection.detail(progress: scanProgress) : snapshot.currentDetail)
                            .font(.system(size: 15 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Care.headingMuted)
                            .contentTransition(.opacity)
                    }
                    .frame(height: 66 * scale)

                    scanRow(
                        sections: ActiveScanSection.topSections,
                        activeSection: activeSection,
                        contentWidth: contentWidth,
                        height: topRowHeight,
                        scale: scale
                    )

                    scanRow(
                        sections: ActiveScanSection.bottomSections,
                        activeSection: activeSection,
                        contentWidth: contentWidth,
                        height: bottomRowHeight,
                        scale: scale
                    )
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 94)
                .overlay(alignment: .bottom) {
                    StopScanButton(progress: scanProgress, pulse: pulse, action: onStop)
                        .frame(width: 94 * scale, height: 94 * scale)
                        .offset(y: 22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func scanRow(
        sections: [ActiveScanSection],
        activeSection: ActiveScanSection,
        contentWidth: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> some View {
        let hasActiveSection = sections.contains(activeSection)
        let compactWidth = min(236 * scale, contentWidth * 0.32)
        let totalSpacing = CGFloat(max(sections.count - 1, 0)) * 16
        let activeWidth = max(contentWidth * 0.42, contentWidth - (compactWidth * CGFloat(max(sections.count - 1, 0))) - totalSpacing)
        let regularWidth = (contentWidth - totalSpacing) / CGFloat(max(sections.count, 1))

        return HStack(spacing: 16) {
            ForEach(sections) { section in
                let isActive = section == activeSection

                ScanningTaskCard(
                    section: section,
                    isActive: isActive,
                    snapshot: snapshot,
                    progress: isActive ? section.sectionProgress(overallProgress: scanProgress) : section.passiveProgress(overallProgress: scanProgress),
                    pulse: pulse
                )
                .frame(width: hasActiveSection ? (isActive ? activeWidth : compactWidth) : regularWidth)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: activeSection)
    }
}

private enum ActiveScanSection: String, CaseIterable, Identifiable {
    case cleanup
    case protection
    case performance
    case applications
    case myClutter

    var id: String { rawValue }

    static let topSections: [ActiveScanSection] = [.cleanup, .protection, .performance]
    static let bottomSections: [ActiveScanSection] = [.applications, .myClutter]

    init(progress: Double) {
        switch progress {
        case 0..<0.42:
            self = .cleanup
        case 0.42..<0.58:
            self = .protection
        case 0.58..<0.73:
            self = .performance
        case 0.73..<0.87:
            self = .applications
        default:
            self = .myClutter
        }
    }

    var title: String {
        switch self {
        case .cleanup:
            "Cleanup"
        case .protection:
            "Protection"
        case .performance:
            "Performance"
        case .applications:
            "Applications"
        case .myClutter:
            "My Clutter"
        }
    }

    var symbolName: String {
        switch self {
        case .cleanup:
            "face.smiling.inverse"
        case .protection:
            "shield.lefthalf.filled"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }

    var logCategory: CareLogCategory {
        switch self {
        case .cleanup:
            .cleanup
        case .protection:
            .protection
        case .performance:
            .performance
        case .applications:
            .applications
        case .myClutter:
            .myClutter
        }
    }

    var headline: String {
        switch self {
        case .cleanup:
            "Scanning junk"
        case .protection:
            "Checking protection"
        case .performance:
            "Scanning performance"
        case .applications:
            "Checking applications"
        case .myClutter:
            "Scanning large files & duplicates"
        }
    }

    func detail(progress: Double) -> String {
        switch self {
        case .cleanup:
            sectionProgress(overallProgress: progress) < 0.5
                ? "Scanning browser junk caches."
                : "Scanning app, log, temp, developer, and package junk."
        case .protection:
            "Checking privacy traces and downloaded installer leftovers."
        case .performance:
            "Scanning login items, launch agents, and background helpers."
        case .applications:
            "Checking installed applications."
        case .myClutter:
            "Scanning large files and duplicate candidates."
        }
    }

    func value(progress: Double) -> String {
        let progress = max(0, min(progress, 1))

        switch self {
        case .cleanup:
            return progress < 1 ? "Scanning..." : "Junk scan"
        case .protection:
            return progress < 1 ? "Checking..." : "Review"
        case .performance:
            return progress < 1 ? "Scanning..." : "Startups"
        case .applications:
            return progress < 1 ? "Checking..." : "Apps"
        case .myClutter:
            return progress < 1 ? "Scanning..." : "Files"
        }
    }

    func status(progress: Double, isActive: Bool) -> String {
        if !isActive {
            return passiveStatus
        }

        switch self {
        case .cleanup:
            return progress < 0.5 ? "Browser junk" : "Deep system junk"
        case .protection:
            return "Privacy & installers"
        case .performance:
            return "Startup items"
        case .applications:
            return "Installed apps"
        case .myClutter:
            return "Large files & duplicates"
        }
    }

    var passiveStatus: String {
        switch self {
        case .cleanup:
            "Junk"
        case .protection:
            "Safety"
        case .performance:
            "Startups"
        case .applications:
            "Apps"
        case .myClutter:
            "Files & duplicates"
        }
    }

    func sectionProgress(overallProgress: Double) -> Double {
        let range = progressRange
        return max(0, min((overallProgress - range.lowerBound) / (range.upperBound - range.lowerBound), 1))
    }

    func passiveProgress(overallProgress: Double) -> Double {
        overallProgress >= progressRange.upperBound ? 1 : 0
    }

    private var progressRange: Range<Double> {
        switch self {
        case .cleanup:
            0..<0.42
        case .protection:
            0.42..<0.58
        case .performance:
            0.58..<0.73
        case .applications:
            0.73..<0.87
        case .myClutter:
            0.87..<1.01
        }
    }
}

private struct ScanningTaskCard: View {
    let section: ActiveScanSection
    let isActive: Bool
    let snapshot: CareScanSnapshot
    let progress: Double
    let pulse: Bool

    private var accent: FeatureAccent { section.logCategory.accent }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? accent.tint.opacity(0.4) : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isActive ? accent.solid.opacity(0.4) : AppTheme.Colors.border,
                            lineWidth: isActive ? 1.5 : 1
                        )
                }
                .shadow(
                    color: isActive ? Color.black.opacity(0.10) : Color.black.opacity(0.04),
                    radius: isActive ? 14 : 6,
                    y: isActive ? 6 : 3
                )

            ResultCardBadge(
                result: ScanResult(
                    category: section.logCategory,
                    title: section.title,
                    value: "",
                    status: "",
                    symbolName: section.symbolName,
                    backgroundColors: [],
                    badgeColors: [AppTheme.Colors.textTertiary, AppTheme.Colors.accentStrong],
                    badgeRotation: section == .performance || section == .myClutter ? 8 : -8,
                    isWide: true
                )
            )
            .frame(width: isActive ? 150 : 118, height: isActive ? 126 : 100)
            .offset(x: isActive ? 118 : 86, y: isActive ? -24 : -20)
            .opacity(isActive ? 0.7 : 0.28)
            .scaleEffect(isActive && pulse ? 1.04 : 1)

            VStack(alignment: .leading, spacing: isActive ? 14 : 8) {
                Text(section.title)
                    .font(.system(size: isActive ? 20 : 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Care.cardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 6)

                Text(value)
                    .font(.system(size: isActive ? 38 : 25, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Care.cardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .contentTransition(.numericText())

                Text(section.status(progress: progress, isActive: isActive))
                    .font(.system(size: isActive ? 16 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Care.cardSubtext)
                    .lineLimit(1)

                if isActive {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(accent.solid)
                        .scaleEffect(x: 1, y: 0.7, anchor: .center)
                        .padding(.top, 2)
                }
            }
            .padding(isActive ? 24 : 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isActive ? 1 : 0.68)
    }

    private var value: String {
        if isActive {
            switch section {
            case .cleanup:
                return snapshot.cacheItems > 0 ? snapshot.formattedCacheSize : "Scanning..."
            case .protection:
                return snapshot.protectionItems > 0 ? snapshot.protectionSummary : "Checking..."
            case .performance:
                return snapshot.startupItems > 0 ? snapshot.startupSummary : "Scanning..."
            case .applications:
                return snapshot.appsChecked > 0 ? snapshot.appSummary : "Checking..."
            case .myClutter:
                return snapshot.largeFiles + snapshot.duplicateFiles > 0 ? snapshot.clutterSummary : "Scanning..."
            }
        }

        guard progress >= 1 else {
            return "Queued"
        }

        switch section {
        case .cleanup:
            return snapshot.formattedCacheSize
        case .protection:
            return snapshot.protectionSummary
        case .performance:
            return snapshot.startupSummary
        case .applications:
            return snapshot.appSummary
        case .myClutter:
            return snapshot.clutterSummary
        }
    }
}

private struct ScanningTopBar: View {
    var body: some View {
        HStack {
            Spacer()

            Button("Unlock Full Version") {}
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .buttonStyle(.appInteractive)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(FeatureAccent.dashboard.gradient)
                }
                .accentGlow(.dashboard, radius: 12, y: 5)
                .raisedButtonChrome(cornerRadius: 21)
        }
        .frame(height: 48)
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) {
            Text("Care")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Care.headingMuted)
        }
    }
}

private struct CurrentScanCard: View {
    let title: String
    let subtitle: String
    let progress: Double
    let pulse: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .contentTransition(.opacity)

                Spacer(minLength: 24)

                CurrentScanBadge(pulse: pulse)
                    .frame(width: 230, height: 170)
                    .padding(.bottom, 34)

                Spacer(minLength: 18)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.opacity)
            }
            .padding(.top, 34)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CurrentScanBadge: View {
    let pulse: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(AppTheme.Colors.border.opacity(0.5))
                .frame(width: 228, height: 142)
                .blur(radius: pulse ? 3 : 7)
                .scaleEffect(pulse ? 1.04 : 0.96)

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(AppTheme.Colors.glassStrong)
                .frame(width: 218, height: 142)
                .rotationEffect(.degrees(1.5))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1.5)
                }

            Image(systemName: "magnifyingglass")
                .font(.system(size: 78, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.7))
        }
    }
}

private struct ScanningPreviewCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbolName: String
    let badgeOffset: CGSize
    let dimmed: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineSpacing(5)
                        .minimumScaleFactor(0.7)

                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .opacity(dimmed ? 0.72 : 1)
    }
}

private struct ScanningWidePreviewCard: View {
    let title: String
    let symbolName: String
    let badgeOffset: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .opacity(0.78)
    }
}

private struct StopScanButton: View {
    let progress: Double
    let pulse: Bool
    let action: () -> Void
    @State private var isAnimating = false

    var body: some View {
        Button(action: action) {
            Text("Stop")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        Circle()
                            .fill(FeatureAccent.dashboard.gradient)

                        Circle()
                            .trim(from: 0.08, to: 0.88)
                            .stroke(AppTheme.Colors.border.opacity(0.92), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(isAnimating ? 360 : 0))
                            .padding(-6)
                            .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: isAnimating)

                        Circle()
                            .stroke(.white.opacity(0.52), lineWidth: 2)
                    }
                    .accentGlow(.dashboard, radius: 24, y: 8)
                }
                .contentShape(Circle())
                .raisedCircleButtonChrome()
        }
        .buttonStyle(.appInteractive)
        .onAppear {
            isAnimating = true
        }
        .accessibilityLabel("Stop scan")
    }
}
