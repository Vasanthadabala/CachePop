//
//  DashboardView.swift
//  CachePop
//
//  Created by Vasanth on 13/05/26.
//

import SwiftUI

struct DashboardView: View {
    @State private var selectedItem: DashboardSidebarItem = .smartCare
    @State private var scanPhase: ScanPhase = .idle
    @State private var scanProgress = 0.0
    @State private var scanTask: Task<Void, Never>?
    @State private var pulse = false

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let scale = min(max(proxy.size.width / 1180, 0.78), 1.08)

                ZStack(alignment: .topLeading) {
                    DashboardSectionBackground(selectedItem: selectedItem)

                    HStack(spacing: 0) {
                        DashboardSidebar(selectedItem: $selectedItem)
                            .frame(width: 250)

                        Group {
                            if selectedItem == .smartCare, scanPhase == .complete {
                                DashboardResultsContent(onStartOver: resetScan)
                            } else if selectedItem == .cleanup {
                                CleanUpView {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                        selectedItem = .smartCare
                                    }
                                }
                            } else if selectedItem == .protection {
                                ProtectionView {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                        selectedItem = .smartCare
                                    }
                                }
                            } else if selectedItem == .performance {
                                PerformanceView {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                        selectedItem = .smartCare
                                    }
                                }
                            } else if selectedItem == .applications {
                                ApplicationsView {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                        selectedItem = .smartCare
                                    }
                                }
                            } else if selectedItem == .myClutter {
                                MyClutterView {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                        selectedItem = .smartCare
                                    }
                                }
                            } else if selectedItem == .assistant {
                                AssistanceView()
                            } else {
                                DashboardHomeContent(
                                    scanPhase: scanPhase,
                                    scanProgress: scanProgress,
                                    pulse: pulse,
                                    scale: scale,
                                    onScan: startScan
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func startScan() {
        guard scanPhase != .scanning else { return }

        scanTask?.cancel()
        scanProgress = 0

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            scanPhase = .scanning
        }

        scanTask = Task {
            for step in 1...100 {
                try? await Task.sleep(for: .milliseconds(100))

                if Task.isCancelled {
                    return
                }

                await MainActor.run {
                    withAnimation(.linear(duration: 0.09)) {
                        scanProgress = Double(step) / 100
                    }
                }
            }

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    scanPhase = .complete
                }
            }
        }
    }

    private func resetScan() {
        scanTask?.cancel()
        scanTask = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            scanProgress = 0
            scanPhase = .idle
            selectedItem = .smartCare
        }
    }
}

private struct DashboardHomeContent: View {
    let scanPhase: ScanPhase
    let scanProgress: Double
    let pulse: Bool
    let scale: CGFloat
    let onScan: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: 70)

                ComputerScanHero(
                    scanPhase: scanPhase,
                    scanProgress: scanProgress,
                    pulse: pulse,
                    onScan: onScan
                )
                .frame(width: 520 * scale, height: 360 * scale)

                VStack(spacing: 16) {
                    Text("Welcome to CachePop")
                        .font(.system(size: 42 * scale, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(subtitle)
                        .font(.system(size: 17 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .contentTransition(.numericText())
                }
                .padding(.top, 12)

                Spacer(minLength: 74)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("by CachePop")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.trailing, 30)
                .padding(.bottom, 28)
        }
    }

    private var subtitle: String {
        switch scanPhase {
        case .idle:
            "Start with a quick and extensive scan of your Mac."
        case .scanning:
            "Scanning your Mac... \(Int(scanProgress * 100))% complete."
        case .complete:
            "Your Mac is in great shape."
        }
    }
}

private struct ComputerScanHero: View {
    let scanPhase: ScanPhase
    let scanProgress: Double
    let pulse: Bool
    let onScan: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let screenWidth = width * 0.82
            let screenHeight = height * 0.54
            let standWidth = width * 0.23
            let standHeight = height * 0.25
            let baseWidth = width * 0.43

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: 0x86A6FF).opacity(0.42),
                                Color(hex: 0x1B14A0).opacity(0.26),
                                .clear
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: width * 0.4
                        )
                    )
                    .frame(width: width * 0.68, height: height * 0.11)
                    .blur(radius: 8)
                    .offset(y: height * 0.34)

                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0xEEF2FF),
                                        Color(hex: 0x7D98F6),
                                        Color(hex: 0x2D1A88)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(hex: 0x1A1268).opacity(0.35), radius: 22, y: 12)

                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.7),
                                        .white.opacity(0.12),
                                        .black.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )

                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 26,
                                bottomLeading: 7,
                                bottomTrailing: 26,
                                topTrailing: 7
                            )
                        )
                        .fill(.black.opacity(0.13))
                        .frame(width: screenWidth * 0.82, height: screenHeight * 0.38)
                        .rotationEffect(.degrees(4))
                        .offset(y: screenHeight * 0.14)

                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.white.opacity(0.13))
                            .frame(width: screenWidth * 0.92, height: screenHeight * 0.42)
                            .blur(radius: 18)
                            .offset(y: -screenHeight * 0.2)

                        ScanButton(
                            scanPhase: scanPhase,
                            progress: scanProgress,
                            pulse: pulse,
                            action: onScan
                        )
                            .frame(width: screenHeight * 0.43, height: screenHeight * 0.43)
                    }
                    .frame(width: screenWidth, height: screenHeight)

                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0xF4F1FF),
                                        Color(hex: 0xB9B2CF),
                                        Color(hex: 0xEEEAFE)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: standWidth, height: standHeight)

                        Circle()
                            .fill(.white.opacity(0.22))
                            .frame(width: standWidth * 0.34, height: standWidth * 0.34)
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: standWidth * 0.13, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x5B69D8).opacity(0.42))
                            }
                            .padding(.top, standHeight * 0.22)
                    }

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xF5F2FF),
                                    Color(hex: 0xBEB7CF)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: baseWidth, height: height * 0.035)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(.white.opacity(0.55))
                                .frame(height: 2)
                        }
                }
                .offset(y: -height * 0.02)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ScanButton: View {
    let scanPhase: ScanPhase
    let progress: Double
    let pulse: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .scaleEffect(pulse ? 1.28 : 0.96)
                    .opacity(scanPhase == .scanning ? 0.18 : (pulse ? 0.22 : 0.52))

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xDCE6FF),
                                Color(hex: 0x6F8DFF),
                                Color(hex: 0x3720B0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.8), lineWidth: 2)
                    }
                    .shadow(color: Color(hex: 0x6F8DFF).opacity(0.52), radius: 22, y: 10)

                if scanPhase == .scanning {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            .white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(5)
                }

                VStack(spacing: 5) {
                    Image(systemName: iconName)
                        .font(.system(size: scanPhase == .scanning ? 17 : 21, weight: .bold))

                    Text(title)
                        .font(.system(size: scanPhase == .scanning ? 13 : 17, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(scanPhase == .scanning)
        .accessibilityLabel(scanPhase == .scanning ? "Scan in progress" : "Start scan")
    }

    private var iconName: String {
        scanPhase == .scanning ? "waveform.path.ecg.magnifyingglass" : "magnifyingglass"
    }

    private var title: String {
        scanPhase == .scanning ? "\(Int(progress * 100))%" : "Scan"
    }
}

private struct DashboardResultsContent: View {
    let onStartOver: () -> Void

    private let topResults = ScanResult.topResults
    private let bottomResults = ScanResult.bottomResults

    var body: some View {
        VStack(spacing: 0) {
            ResultsTopBar(onStartOver: onStartOver)

            Spacer(minLength: 56)

            Text("Well done! Your Mac is in great shape!")
                .font(.system(size: 38, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.bottom, 34)

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ForEach(topResults) { result in
                        ScanResultCard(result: result)
                    }
                }
                .frame(height: 206)

                HStack(spacing: 16) {
                    ForEach(bottomResults) { result in
                        ScanResultCard(result: result)
                    }
                }
                .frame(height: 182)
            }
            .padding(.horizontal, 34)

            Spacer(minLength: 28)

            HStack {
                Spacer()

                Button("View Log") {}
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 17)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("View scan log")
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct ResultsTopBar: View {
    let onStartOver: () -> Void

    var body: some View {
        HStack {
            Button(action: onStartOver) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))

                    Text("Start Over")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start over")

            Spacer()
        }
        .frame(height: 28)
        .padding(.top, 26)
        .padding(.horizontal, 34)
        .overlay(alignment: .bottom) {
            Text("Smart Care")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
    }
}

private struct CompactResultsSidebar: View {
    var body: some View {
        VStack(spacing: 31) {
            Spacer()
                .frame(height: 160)

            ForEach(DashboardSidebarItem.mainItems) { item in
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(item == .smartCare ? .white.opacity(0.12) : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(item == .smartCare ? .white.opacity(0.16) : .clear, lineWidth: 1)
                        }
                        .frame(width: 56, height: 56)

                    Image(systemName: item.symbolName)
                        .font(.system(size: 23, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.iconColor)
                        .frame(width: 56, height: 56)

                    if item == .smartCare || item == .applications {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white.opacity(0.92))
                            .offset(x: 7, y: -7)
                    }
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 34, height: 34)

                Image(systemName: DashboardSidebarItem.assistant.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DashboardSidebarItem.assistant.iconColor)
            }
            .padding(.bottom, 42)
        }
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.white.opacity(0.028))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1)
                }
        }
    }
}

private struct ScanResultCard: View {
    let result: ScanResult

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: result.backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            ResultCardBadge(result: result)
                .frame(width: result.isWide ? 150 : 136, height: result.isWide ? 150 : 136)
                .offset(x: result.isWide ? 38 : 24, y: result.isWide ? -24 : -28)

            VStack(alignment: .leading, spacing: 0) {
                Text(result.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                Text(result.value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))

                    Text(result.status)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color(hex: 0xBFD0FF))
                .padding(.top, 10)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ResultCardBadge: View {
    let result: ScanResult

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: result.badgeColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(result.badgeRotation))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 8)

            Image(systemName: result.symbolName)
                .font(.system(size: 48, weight: .heavy))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.84))
        }
    }
}

private struct ScanResult: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let status: String
    let symbolName: String
    let backgroundColors: [Color]
    let badgeColors: [Color]
    let badgeRotation: Double
    let isWide: Bool

    static let topResults: [ScanResult] = [
        ScanResult(
            title: "Cleanup",
            value: "40,9 GB of junk",
            status: "Cleaned",
            symbolName: "face.smiling.inverse",
            backgroundColors: [
                Color(hex: 0x6F3BBA),
                Color(hex: 0x5A4FC4),
                Color(hex: 0x24306D)
            ],
            badgeColors: [
                Color(hex: 0xA8BAFF),
                Color(hex: 0x3D28BF)
            ],
            badgeRotation: -8,
            isWide: false
        ),
        ScanResult(
            title: "Protection",
            value: "4 threats",
            status: "Removed",
            symbolName: "hand.raised.fill",
            backgroundColors: [
                Color(hex: 0x7D27A5),
                Color(hex: 0x9C2B98),
                Color(hex: 0x371064)
            ],
            badgeColors: [
                Color(hex: 0xA9BAFF),
                Color(hex: 0x5530D5)
            ],
            badgeRotation: 4,
            isWide: false
        ),
        ScanResult(
            title: "Performance",
            value: "1 task",
            status: "Done",
            symbolName: "bolt.fill",
            backgroundColors: [
                Color(hex: 0x26136C),
                Color(hex: 0x171052),
                Color(hex: 0x4F4AA8)
            ],
            badgeColors: [
                Color(hex: 0xB9C8FF),
                Color(hex: 0x4D31D8)
            ],
            badgeRotation: 8,
            isWide: false
        )
    ]

    static let bottomResults: [ScanResult] = [
        ScanResult(
            title: "Applications",
            value: "6 vital updates",
            status: "Started",
            symbolName: "sparkles",
            backgroundColors: [
                Color(hex: 0x792A9E),
                Color(hex: 0x7257C5),
                Color(hex: 0x507CC8)
            ],
            badgeColors: [
                Color(hex: 0x91ADFF),
                Color(hex: 0x2D35B8)
            ],
            badgeRotation: -10,
            isWide: true
        ),
        ScanResult(
            title: "My Clutter",
            value: "283 duplicate downloads",
            status: "Removed",
            symbolName: "folder.fill",
            backgroundColors: [
                Color(hex: 0x32106D),
                Color(hex: 0x20105F),
                Color(hex: 0x4756B8)
            ],
            badgeColors: [
                Color(hex: 0x8EA8FF),
                Color(hex: 0x2A26A8)
            ],
            badgeRotation: 8,
            isWide: true
        )
    ]
}

private enum ScanPhase {
    case idle
    case scanning
    case complete
}

private struct DashboardSidebar: View {
    @Binding var selectedItem: DashboardSidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
                .frame(height: 90)

            ForEach(DashboardSidebarItem.mainItems) { item in
                SidebarButton(
                    item: item,
                    isSelected: selectedItem == item
                ) {
                    selectedItem = item
                }
            }

            Spacer()

            SidebarButton(
                item: .assistant,
                isSelected: selectedItem == .assistant
            ) {
                selectedItem = .assistant
            }
            .padding(.bottom, 42)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
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

private struct SidebarButton: View {
    let item: DashboardSidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            }
                            .frame(width: 54, height: 48)
                    }

                    Image(systemName: item.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.iconColor)
                        .frame(width: 42, height: 42)
                }

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .frame(height: 58)
            .padding(.horizontal, isSelected ? 16 : 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}

private enum DashboardSidebarItem: String, CaseIterable, Identifiable {
    case smartCare
    case cleanup
    case protection
    case performance
    case applications
    case myClutter
    case assistant

    var id: String { rawValue }

    static let mainItems: [DashboardSidebarItem] = [
        .smartCare,
        .cleanup,
        .protection,
        .performance,
        .applications,
        .myClutter
    ]

    var title: String {
        switch self {
        case .smartCare:
            "Smart Care"
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
        case .assistant:
            "Assistant"
        }
    }

    var symbolName: String {
        switch self {
        case .smartCare:
            "desktopcomputer"
        case .cleanup:
            "face.smiling.inverse"
        case .protection:
            "hand.raised.fill"
        case .performance:
            "bolt.fill"
        case .applications:
            "shippingbox.fill"
        case .myClutter:
            "folder.fill"
        case .assistant:
            "circle.grid.cross.fill"
        }
    }

    var iconColor: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0xFFFFFF).opacity(0.95),
                Color(hex: 0xD4C4FF).opacity(0.82),
                Color(hex: 0xFF63DA).opacity(self == .smartCare ? 0.95 : 0.48)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct DashboardSectionBackground: View {
    let selectedItem: DashboardSidebarItem

    var body: some View {
        SectionGradientBackground(
            colors: [
                Color(hex: 0x4D42AD),
                Color(hex: 0x655FE1),
                Color(hex: 0x13084B)
            ],
            glow: Color(hex: 0x86A6FF),
            glowCenter: selectedItem == .smartCare ? UnitPoint(x: 0.64, y: 0.24) : UnitPoint(x: 0.26, y: 0.22)
        )
    }
}

private struct SectionGradientBackground: View {
    let colors: [Color]
    let glow: Color
    let glowCenter: UnitPoint

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    glow.opacity(0.62),
                    glow.opacity(0.28),
                    .clear
                ],
                center: glowCenter,
                startRadius: 20,
                endRadius: 640
            )

            RadialGradient(
                colors: [
                    .white.opacity(0.3),
                    Color(hex: 0xDCE6FF).opacity(0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.18),
                startRadius: 12,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x1F14A8).opacity(0.48),
                    .clear
                ],
                center: UnitPoint(x: 0.3, y: 0.72),
                startRadius: 30,
                endRadius: 580
            )

            LinearGradient(
                colors: [
                    .white.opacity(0.08),
                    .clear,
                    .black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x240060),
                    Color(hex: 0x8C16A9),
                    Color(hex: 0x080039)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xFF1BD8).opacity(0.48),
                    Color(hex: 0x7C15A8).opacity(0.22),
                    .clear
                ],
                center: UnitPoint(x: 0.64, y: 0.24),
                startRadius: 20,
                endRadius: 480
            )

            RadialGradient(
                colors: [
                    Color(hex: 0x7E2FFF).opacity(0.5),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: 0.76),
                startRadius: 20,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.1),
                    .black.opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

#Preview {
    DashboardView()
        .frame(width: 1180, height: 760)
}
