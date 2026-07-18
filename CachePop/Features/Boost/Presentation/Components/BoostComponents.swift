import SwiftUI

struct PerformanceIntroContent: View {
    let onScan: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 1080, 0.78), 1.04)

            ZStack(alignment: .topTrailing) {
                PerformanceUnlockButton(scale: scale)

                HStack(spacing: 74 * scale) {
                    PerformanceBadge()
                        .frame(width: 390 * scale, height: 360 * scale)
                        .offset(y: 18 * scale)

                    VStack(alignment: .leading, spacing: 34 * scale) {
                        VStack(alignment: .leading, spacing: 22 * scale) {
                            Text("Performance")
                                .font(.system(size: 54 * scale, weight: .light, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Text("Keep your Mac in top shape with\nrecommended maintenance.")
                                .font(.system(size: 22 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                                .lineSpacing(6)
                        }
                        .padding(.bottom, 18 * scale)

                        PerformanceFeatureRow(symbolName: "wrench.and.screwdriver.fill", title: "Maintenance Tasks", scale: scale)
                        PerformanceFeatureRow(symbolName: "power", title: "Login Items", scale: scale)
                        PerformanceFeatureRow(symbolName: "rocket.fill", title: "Background Items", scale: scale)

                        PerformanceCircleButton(title: "Scan", progress: nil, scale: scale, action: onScan)
                            .frame(width: 104 * scale, height: 104 * scale)
                            .padding(.top, 24 * scale)
                            .padding(.leading, 32 * scale)
                    }
                    .frame(width: 430 * scale, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -24 * scale)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

struct PerformanceScanningContent: View {
    let progress: Double
    let currentPath: String
    let onStop: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 1080, 0.78), 1.04)

            ZStack(alignment: .topTrailing) {
                Text("Performance")
                    .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 28)

                PerformanceUnlockButton(scale: scale)

                VStack(spacing: 0) {
                    PerformanceBadge()
                        .frame(width: 330 * scale, height: 300 * scale)
                        .padding(.top, 96 * scale)

                    Spacer(minLength: 42)

                    Text("Examining your system...")
                        .font(.system(size: 42 * scale, weight: .light, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(currentPath)
                        .font(.system(size: 18 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .padding(.top, 18 * scale)
                        .padding(.horizontal, 80)

                    Spacer(minLength: 128 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PerformanceCircleButton(title: "Stop", progress: progress, scale: scale, action: onStop)
                    .frame(width: 104 * scale, height: 104 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 42 * scale)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

struct PerformanceReadyContent: View {
    let startupDetails: [CareScanDetailItem]
    let onStartOver: () -> Void
    let onViewAllTasks: () -> Void
    let onReview: (PerformanceSection) -> Void

    private var loginItems: [CareScanDetailItem] {
        startupDetails.filter { $0.kind == "Login Item" }
    }

    private var backgroundItems: [CareScanDetailItem] {
        startupDetails.filter { $0.kind == "Background Item" }
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 1080, 0.78), 1.04)

            ZStack(alignment: .topTrailing) {
                HStack {
                    Button(action: onStartOver) {
                        HStack(spacing: 9) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 17 * scale, weight: .bold))

                            Text("Start Over")
                                .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))
                    }
                    .buttonStyle(.appInteractive)

                    Spacer()

                    Text("Performance")
                        .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))

                    Spacer()
                        .frame(width: 118 * scale)
                }
                .padding(.top, 28)
                .padding(.horizontal, 28)

                PerformanceUnlockButton(scale: scale)

                VStack(spacing: 0) {
                    PerformanceBadge()
                        .frame(width: 250 * scale, height: 220 * scale)
                        .padding(.top, 96 * scale)

                    Text("Apply curated recommendations\nor run performance tasks manually.")
                        .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8 * scale)
                        .minimumScaleFactor(0.72)
                        .padding(.top, 28 * scale)

                    Button("View All Tasks", action: onViewAllTasks)
                        .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .buttonStyle(.appInteractive)
                        .padding(.horizontal, 22 * scale)
                        .frame(height: 42 * scale)
                        .background {
                            Capsule(style: .continuous)
                                .fill(FeatureAccent.boost.gradient)
                        }
                        .accentGlow(.boost, radius: 12, y: 5)
                        .raisedButtonChrome(cornerRadius: 21)
                        .padding(.top, 26 * scale)

                    Spacer()

                    HStack(spacing: 18 * scale) {
                        PerformanceResultCard(
                            title: loginTitle,
                            subtitle: "Review the list of applications that open automatically when you start up your Mac. You may want to disable some of them.",
                            symbolName: "power",
                            isWide: true,
                            action: { onReview(.loginItems) }
                        )

                        PerformanceResultCard(
                            title: backgroundTitle,
                            subtitle: nil,
                            symbolName: "rocket.fill",
                            isWide: false,
                            action: { onReview(.backgroundItems) }
                        )
                        .frame(width: 330 * scale)
                    }
                    .frame(height: 190 * scale)
                    .padding(.horizontal, 34 * scale)
                    .padding(.bottom, 34 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private var loginTitle: String {
        let count = loginItems.count
        return count == 1 ? "You Have 1 Login Item" : "You Have \(count) Login Items"
    }

    private var backgroundTitle: String {
        let count = backgroundItems.count
        return count == 1 ? "1 Background Item\nFound" : "\(count) Background Items\nFound"
    }
}

struct PerformanceResultCard: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isWide: Bool
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)

            ZStack {
                BoostBadgeShape()
                    .fill(FeatureAccent.boost.tint)
                    .overlay {
                        BoostBadgeShape()
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }

                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(FeatureAccent.boost.solid)
            }
            .frame(width: 54, height: 58)
            .padding(.top, 22)
            .padding(.trailing, 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(isWide ? 1 : 2)
                    .minimumScaleFactor(0.72)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 14)
                }

                Spacer()

                HStack {
                    Spacer()

                    Button("Review", action: action)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .buttonStyle(.appInteractive)
                        .frame(width: 78, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(FeatureAccent.boost.gradient)
                        }
                        .raisedButtonChrome(cornerRadius: 8)
                }
            }
            .padding(24)
            .padding(.trailing, isWide ? 98 : 56)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PerformanceUnlockButton: View {
    let scale: CGFloat

    var body: some View {
        Button("Unlock Full Version") {}
            .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.inverseText)
            .buttonStyle(.appInteractive)
            .padding(.horizontal, 22 * scale)
            .frame(height: 42 * scale)
            .background {
                Capsule(style: .continuous)
                    .fill(FeatureAccent.boost.gradient)
            }
            .accentGlow(.boost, radius: 12, y: 5)
            .raisedButtonChrome(cornerRadius: 21 * scale)
            .padding(.top, 28)
            .padding(.trailing, 28)
    }
}

struct PerformanceCircleButton: View {
    let title: String
    let progress: Double?
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(FeatureAccent.boost.gradient)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.78), lineWidth: 2)
                    }
                    .accentGlow(.boost, radius: 28, y: 9)

                if let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white.opacity(0.88), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(5)
                }

                Text(title)
                    .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
            }
            .contentShape(Circle())
            .raisedCircleButtonChrome()
        }
        .buttonStyle(.appInteractive)
    }
}

struct PerformanceFeatureRow: View {
    let symbolName: String
    let title: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 20 * scale) {
            ZStack {
                BoostBadgeShape()
                    .fill(FeatureAccent.boost.gradient)
                    .frame(width: 34 * scale, height: 38 * scale)

                Image(systemName: symbolName)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
        }
    }
}

struct PerformanceCompletePanel: View {
    let onDone: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.05), radius: 12, y: 4)

                PerformanceBadge()
                    .frame(width: min(proxy.size.width * 0.46, 410))
                    .offset(x: -proxy.size.width * 0.1, y: -16)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Removal complete!")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 20) {
                        RocketBadge()
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("8 background items")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("successfully removed")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
                .frame(width: proxy.size.width * 0.46, alignment: .leading)
                .offset(x: proxy.size.width * 0.45)

                Button("View Log") {}
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .buttonStyle(.appInteractive)
                    .padding(.leading, 38)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                HStack(spacing: 16) {
                    Button("Manage More Items") {}
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .buttonStyle(.appInteractive)
                        .frame(width: 154, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.Colors.glassBg)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                                }
                        }
                        .raisedButtonChrome(cornerRadius: 12)

                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(width: 72, height: 40)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(FeatureAccent.boost.gradient)
                            }
                    }
                    .buttonStyle(.appInteractive)
                    .accentGlow(.boost, radius: 8, y: 3)
                    .raisedButtonChrome(cornerRadius: 12)
                }
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

struct PerformanceBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.black.opacity(0.16))
                .frame(width: 356, height: 76)
                .blur(radius: 10)
                .rotationEffect(.degrees(2))
                .offset(y: 130)

            PerformanceChevronShape()
                .fill(FeatureAccent.boost.gradient)
                .overlay {
                    PerformanceChevronShape()
                        .stroke(FeatureAccent.boost.deep.opacity(0.5), lineWidth: 2)
                }
                .accentGlow(.boost, radius: 22, y: 12)

            Image(systemName: "bolt.fill")
                .font(.system(size: 112, weight: .heavy))
                .rotationEffect(.degrees(7))
                .foregroundStyle(.white)
        }
        .aspectRatio(1.15, contentMode: .fit)
    }
}

struct PerformanceChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.17))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.07),
            control: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY - rect.height * 0.04)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.17),
            control: CGPoint(x: rect.maxX - rect.width * 0.29, y: rect.minY - rect.height * 0.04)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.18),
            control: CGPoint(x: rect.maxX + rect.width * 0.02, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.35),
            control: CGPoint(x: rect.maxX - rect.width * 0.23, y: rect.maxY - rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.maxY - rect.height * 0.18),
            control: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.maxY - rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.17),
            control: CGPoint(x: rect.minX - rect.width * 0.02, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

struct RocketBadge: View {
    var body: some View {
        ZStack {
            BoostBadgeShape()
                .fill(FeatureAccent.boost.gradient)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 4)

            Image(systemName: "rocket.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct BoostBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.88))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.72))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.88))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.24))
        path.closeSubpath()
        return path
    }
}

struct PerformanceSidebar: View {
    private let items: [PerformanceSidebarItem] = [
        .smartCare,
        .cleanup,
        .performance,
        .applications,
        .myClutter
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
                .frame(height: 118)

            ForEach(items) { item in
                PerformanceSidebarIcon(item: item)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(AppTheme.Colors.glassBg)
                    .frame(width: 34, height: 34)

                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            AppTheme.Colors.sidebarBg
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(width: 1)
                }
        }
    }
}

struct PerformanceSidebarIcon: View {
    let item: PerformanceSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item == .performance ? Color(hex: 0x111111) : AppTheme.Colors.glassBg)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                }
                .frame(width: 52, height: 52)

            Image(systemName: item.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(item == .performance ? Color.white : AppTheme.Colors.textSecondary)
                .frame(width: 52, height: 52)

            if item == .performance {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .offset(x: 4, y: -4)
            }
        }
    }
}

enum PerformanceSidebarItem: String, Identifiable {
    case smartCare
    case cleanup
    case performance
    case applications
    case myClutter

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        }
    }
}

struct PerformanceBackground: View {
    var body: some View {
        DarkMeshBackground()
    }
}
