//
//  BoostView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct BoostView: View {
    var onDone: () -> Void = {}

    @State private var phase: PerformancePhase = .intro
    @State private var scanProgress = 0.0
    @State private var scanDetail = "Preparing performance scan..."
    @State private var startupDetails: [CareScanDetailItem] = []
    @State private var reviewSection: PerformanceSection?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PerformanceBackground()

            if let reviewSection {
                PerformanceManagerContent(
                    snapshot: performanceSnapshot,
                    initialSection: reviewSection,
                    onBack: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            self.reviewSection = nil
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(10)
            } else {
                switch phase {
                case .intro:
                    PerformanceIntroContent(onScan: startScan)
                case .scanning:
                    PerformanceScanningContent(
                        progress: scanProgress,
                        currentPath: currentPath,
                        onStop: resetScan
                    )
                case .ready:
                    PerformanceReadyContent(
                        startupDetails: startupDetails,
                        onStartOver: resetScan,
                        onViewAllTasks: { showReview(.loginItems) },
                        onReview: showReview
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private var performanceSnapshot: CareScanSnapshot {
        var snapshot = CareScanSnapshot.empty
        snapshot.startupItems = startupDetails.count
        snapshot.startupDetails = startupDetails
        return snapshot
    }

    private func showReview(_ section: PerformanceSection) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            reviewSection = section
        }
    }

    private func startScan() {
        guard phase != .scanning else { return }
        scanTask?.cancel()
        scanProgress = 0
        scanDetail = "Preparing performance scan..."
        startupDetails = []

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .scanning
        }

        scanTask = Task {
            updateScan(progress: 0.12, detail: "Checking apps that open when you log in...")
            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            updateScan(progress: 0.42, detail: "Scanning third-party login items...")
            let result = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanStartupItems()
            }.value
            if Task.isCancelled { return }

            await MainActor.run {
                startupDetails = result.details
            }

            updateScan(progress: 0.72, detail: "Checking third-party background applications and processes...")
            try? await Task.sleep(for: .milliseconds(360))
            if Task.isCancelled { return }

            if let sample = result.details.first(where: { $0.kind == "Background Item" }) ?? result.details.first {
                updateScan(progress: 0.9, detail: sample.path)
            } else {
                updateScan(progress: 0.9, detail: "No third-party startup or background items found")
            }

            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            updateScan(progress: 1, detail: "Performance scan complete")

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .ready
                }
            }
        }
    }

    private func resetScan() {
        scanTask?.cancel()
        scanTask = nil
        scanProgress = 0
        scanDetail = "Preparing performance scan..."
        startupDetails = []

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .intro
        }
    }

    private var currentPath: String {
        scanDetail
    }

    @MainActor
    private func updateScan(progress: Double, detail: String) {
        withAnimation(.linear(duration: 0.18)) {
            scanProgress = progress
            scanDetail = detail
        }
    }
}

private enum PerformancePhase {
    case intro
    case scanning
    case ready
}

private struct PerformanceIntroContent: View {
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

private struct PerformanceScanningContent: View {
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

private struct PerformanceReadyContent: View {
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
                    .buttonStyle(.plain)

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
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 22 * scale)
                        .frame(height: 42 * scale)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                        }
                        .raisedButtonChrome(cornerRadius: 11)
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

private struct PerformanceResultCard: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isWide: Bool
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Care.actionGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1.2)
                }

            ZStack {
                BoostBadgeShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x8EA8FF),
                                Color(hex: 0x5E70DF),
                                Color(hex: 0x3420A8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.9))
            }
            .frame(width: 54, height: 58)
            .padding(.top, 22)
            .padding(.trailing, 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
                    .lineLimit(isWide ? 1 : 2)
                    .minimumScaleFactor(0.72)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.72))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 14)
                }

                Spacer()

                HStack {
                    Spacer()

                    Button("Review", action: action)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                        .buttonStyle(.plain)
                        .frame(width: 78, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                }
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

private struct PerformanceUnlockButton: View {
    let scale: CGFloat

    var body: some View {
        Button("Unlock Full Version") {}
            .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.inverseText)
            .buttonStyle(.plain)
            .padding(.horizontal, 22 * scale)
            .frame(height: 42 * scale)
            .background {
                Capsule(style: .continuous)
                    .fill(AppTheme.Care.actionGradient)
                    .shadow(color: AppTheme.Care.actionShadow, radius: 12, y: 5)
            }
            .raisedButtonChrome(cornerRadius: 21 * scale)
            .padding(.top, 28)
            .padding(.trailing, 28)
    }
}

private struct PerformanceCircleButton: View {
    let title: String
    let progress: Double?
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .blur(radius: 18)
                    .scaleEffect(1.18)

                Circle()
                    .fill(
                        AppTheme.Care.actionGradient
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.78), lineWidth: 2)
                    }
                    .shadow(color: Color(hex: 0x7180FF).opacity(0.32), radius: 24, y: 9)

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
        .buttonStyle(.plain)
    }
}

private struct PerformanceFeatureRow: View {
    let symbolName: String
    let title: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 20 * scale) {
            ZStack {
                BoostBadgeShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x8EA8FF),
                                Color(hex: 0x5E70DF),
                                Color(hex: 0x3420A8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 34 * scale, height: 38 * scale)

                Image(systemName: symbolName)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
            }

            Text(title)
                .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
        }
    }
}

private struct PerformanceCompletePanel: View {
    let onDone: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x8EA8FF).opacity(0.64),
                                Color(hex: 0x697DE5).opacity(0.72),
                                Color(hex: 0x181052).opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.11), lineWidth: 1)
                    }

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
                                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                        }
                    }
                }
                .frame(width: proxy.size.width * 0.46, alignment: .leading)
                .offset(x: proxy.size.width * 0.45)

                Button("View Log") {}
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .buttonStyle(.plain)
                    .padding(.leading, 38)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                HStack(spacing: 16) {
                    Button("Manage More Items") {}
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .buttonStyle(.plain)
                        .frame(width: 154, height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: 0x8EA8FF).opacity(0.92),
                                            Color(hex: 0x8EA8FF).opacity(0.88),
                                            Color(hex: 0x5E70DF).opacity(0.94)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.13), lineWidth: 1)
                                }
                        }
                        .raisedButtonChrome(cornerRadius: 12)

                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(width: 72, height: 40)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: 0x8EA8FF),
                                                Color(hex: 0x8EA8FF),
                                                Color(hex: 0x5E70DF)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .raisedButtonChrome(cornerRadius: 12)
                }
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

private struct PerformanceBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.black.opacity(0.22))
                .frame(width: 356, height: 76)
                .blur(radius: 10)
                .rotationEffect(.degrees(2))
                .offset(y: 130)

            PerformanceChevronShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x6F83EA),
                            Color(hex: 0x83A1FF),
                            Color(hex: 0x3922B2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    PerformanceChevronShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.42),
                                    Color(hex: 0xB7C8FF).opacity(0.56),
                                    .black.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                }
                .shadow(color: .black.opacity(0.34), radius: 13, y: 10)

            PerformanceChevronShape()
                .fill(.white.opacity(0.18))
                .blur(radius: 9)
                .scaleEffect(0.82)
                .offset(x: 18, y: -42)

            Image(systemName: "bolt.fill")
                .font(.system(size: 112, weight: .heavy))
                .rotationEffect(.degrees(7))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.96),
                            Color(hex: 0x6F83EA).opacity(0.86)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(hex: 0x3E1ED0).opacity(0.45), radius: 12, y: 12)
        }
        .aspectRatio(1.15, contentMode: .fit)
    }
}

private struct PerformanceChevronShape: Shape {
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

private struct RocketBadge: View {
    var body: some View {
        ZStack {
            BoostBadgeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x6F83EA),
                            Color(hex: 0x7EA0FF),
                            Color(hex: 0x3320A8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 4)

            Image(systemName: "rocket.fill")
                .font(.system(size: 25, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: 0x6F83EA), Color(hex: 0xAFC2FF))
        }
    }
}

private struct BoostBadgeShape: Shape {
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

private struct PerformanceSidebar: View {
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
                    .fill(.white.opacity(0.24))
                    .frame(width: 34, height: 34)

                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.82), Color(hex: 0xDCE4FF).opacity(0.6))
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.white.opacity(0.03))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 1)
                }
        }
    }
}

private struct PerformanceSidebarIcon: View {
    let item: PerformanceSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .performance ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .performance ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), Color(hex: 0xFFB159).opacity(item == .performance ? 0.95 : 0.45))
                .frame(width: 58, height: 58)

            if item == .performance {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private enum PerformanceSidebarItem: String, Identifiable {
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

private struct PerformanceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.Colors.appBackground,
                    AppTheme.Colors.appBackground,
                    AppTheme.Colors.appBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.42, y: 0.72),
                startRadius: 18,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.63, y: 0.08),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .clear,
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    BoostView()
        .frame(width: 1180, height: 760)
}
