//
//  JunkCleanerView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import SwiftUI

struct JunkCleanerView: View {
    var onDone: () -> Void = {}

    @State private var phase: CleanupPhase = .intro
    @State private var scanProgress = 0.0
    @State private var scanSnapshot = CareScanSnapshot.empty
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CleanupBackground()

            switch phase {
            case .intro:
                CleanupIntroContent(onScan: startScan)
            case .scanning:
                CleanupScanningContent(
                    progress: scanProgress,
                    currentPath: currentPath,
                    onStartOver: resetCleanup
                )
            case .found:
                CleanupFoundContent(
                    snapshot: scanSnapshot,
                    onStartOver: resetCleanup,
                    onClean: finishCleaning
                )
            case .complete:
                ZStack(alignment: .top) {
                    CleanupTopBar(title: "Junk Cleaner", showsStartOver: true, onStartOver: resetCleanup)

                    CleanupCompletePanel(cleanedSize: scanSnapshot.formattedCacheSize, onDone: onDone)
                        .padding(.leading, 92)
                        .padding(.trailing, 82)
                        .padding(.top, 118)
                        .padding(.bottom, 82)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func startScan() {
        guard phase != .scanning else { return }
        scanTask?.cancel()
        scanProgress = 0
        scanSnapshot = .empty

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .scanning
        }

        scanTask = Task {
            var snapshot = CareScanSnapshot.empty

            updateScan(progress: 0.06, snapshot: snapshot.withCleanupDetail("Preparing local junk scan..."))
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }

            updateScan(progress: 0.18, snapshot: snapshot.withCleanupDetail("Scanning Safari, Chrome, Firefox, Edge, Brave, Arc, and other browser caches."))
            let browserCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanBrowserCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += browserCacheResult.bytes
            snapshot.cacheItems += browserCacheResult.items
            snapshot.cacheDetails.append(contentsOf: browserCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: browserCacheResult.permissions)

            updateScan(progress: 0.46, snapshot: snapshot.withCleanupDetail("Scanning application caches, HTTP storage, WebKit data, saved states, and logs."))
            let appCacheResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanApplicationCaches()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += appCacheResult.bytes
            snapshot.cacheItems += appCacheResult.items
            snapshot.cacheDetails.append(contentsOf: appCacheResult.details)
            snapshot.permissionMessages.append(contentsOf: appCacheResult.permissions)

            updateScan(progress: 0.74, snapshot: snapshot.withCleanupDetail("Scanning Trash Bins and removable junk candidates."))
            let trashResult = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanTrashItems()
            }.value
            if Task.isCancelled { return }
            snapshot.cacheBytes += trashResult.bytes
            snapshot.cacheItems += trashResult.items
            snapshot.cacheDetails.append(contentsOf: trashResult.details)
            snapshot.permissionMessages.append(contentsOf: trashResult.permissions)

            updateScan(progress: 1, snapshot: snapshot.withCleanupDetail("Junk scan complete."))
            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .found
                }
            }
        }
    }

    private func resetCleanup() {
        scanTask?.cancel()
        scanTask = nil
        scanProgress = 0
        scanSnapshot = .empty

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .intro
        }
    }

    private func finishCleaning() {
        scanTask?.cancel()
        scanTask = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .complete
        }
    }

    private var currentPath: String {
        scanSnapshot.currentDetail
    }

    @MainActor
    private func updateScan(progress: Double, snapshot: CareScanSnapshot) {
        withAnimation(.linear(duration: 0.18)) {
            scanProgress = progress
            scanSnapshot = snapshot
        }
    }
}

private extension CareScanSnapshot {
    func withCleanupDetail(_ detail: String) -> CareScanSnapshot {
        var snapshot = self
        snapshot.currentDetail = detail
        return snapshot
    }
}

private enum CleanupPhase {
    case intro
    case scanning
    case found
    case complete
}

private struct CleanupIntroContent: View {
    let onScan: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 930, 0.82), 1.05)

            ZStack {
                CleanupTopBar(title: "", showsStartOver: false, onStartOver: {})

                HStack(spacing: 74 * scale) {
                    CleanupDisk()
                        .frame(width: 390 * scale, height: 390 * scale)

                    VStack(alignment: .leading, spacing: 30 * scale) {
                        VStack(alignment: .leading, spacing: 18 * scale) {
                            Text("Junk Cleaner")
                                .font(.system(size: 54 * scale, weight: .light, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.74)

                            Text("Clean your system to achieve maximum\nperformance and reclaim more free space.")
                                .font(.system(size: 22 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                                .lineSpacing(6)
                        }
                        .padding(.bottom, 16 * scale)

                        CleanupFeatureRow(symbolName: "archivebox.fill", title: "System Junk", scale: scale)
                        CleanupFeatureRow(symbolName: "envelope.fill", title: "Mail Attachments", scale: scale)
                        CleanupFeatureRow(symbolName: "trash.fill", title: "Trash Bins", scale: scale)
                    }
                    .frame(width: 430 * scale, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -26 * scale)

                CleanupCircleButton(title: "Scan", action: onScan)
                    .frame(width: 104 * scale, height: 104 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 22 * scale)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

private struct CleanupFeatureRow: View {
    let symbolName: String
    let title: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 20 * scale) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x9CEB78), Color(hex: 0x257A2C)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 34 * scale, height: 34 * scale)

                Image(systemName: symbolName)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.88))
            }

            Text(title)
                .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
        }
    }
}

private struct CleanupScanningContent: View {
    let progress: Double
    let currentPath: String
    let onStartOver: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 930, 0.82), 1.05)

            ZStack {
                CleanupTopBar(title: "Junk Cleaner", showsStartOver: true, onStartOver: onStartOver)

                VStack(spacing: 0) {
                    CleanupDisk()
                        .frame(width: 430 * scale, height: 430 * scale)
                        .padding(.top, 94 * scale)

                    Spacer(minLength: 42)

                    Text("Looking for junk...")
                        .font(.system(size: 46 * scale, weight: .light, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(currentPath)
                        .font(.system(size: 20 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .padding(.top, 18 * scale)
                        .padding(.horizontal, 70)

                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: min(proxy.size.width * 0.46, 420))
                        .scaleEffect(x: 1, y: 0.72, anchor: .center)
                        .padding(.top, 24 * scale)

                    Spacer(minLength: 96)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

private struct CleanupFoundContent: View {
    let snapshot: CareScanSnapshot
    let onStartOver: () -> Void
    let onClean: () -> Void

    private var cards: [CleanupJunkSummary] {
        CleanupJunkSummary.makeSummaries(from: snapshot)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(proxy.size.width / 930, 0.8), 1.04)
            let hasFindings = snapshot.cacheItems > 0

            ZStack {
                CleanupTopBar(title: "Junk Cleaner", showsStartOver: true, onStartOver: onStartOver)

                VStack(spacing: 0) {
                    CleanupDisk()
                        .frame(width: 210 * scale, height: 210 * scale)
                        .padding(.top, 104 * scale)

                    Text(hasFindings ? "There are \(snapshot.formattedCacheSize) of junk files on your Mac." : "No junk files found on your Mac.")
                        .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.top, 78 * scale)

                    Button("Review All Junk") {}
                        .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24 * scale)
                        .frame(height: 44 * scale)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(.white.opacity(0.18), lineWidth: 1)
                                }
                        }
                        .padding(.top, 26 * scale)
                        .opacity(hasFindings ? 1 : 0.55)
                        .disabled(!hasFindings)

                    Spacer(minLength: 40)

                    HStack(spacing: 18 * scale) {
                        ForEach(cards) { card in
                            CleanupJunkCard(
                                title: card.title,
                                subtitle: card.subtitle,
                                symbolName: card.symbolName,
                                isWide: card.isWide,
                                onClean: hasFindings && card.isPrimary ? onClean : nil
                            )
                            .frame(width: card.isWide ? nil : 300 * scale)
                            .frame(maxWidth: card.isWide ? .infinity : nil)
                        }
                    }
                    .frame(height: 202 * scale)
                    .padding(.horizontal, 42 * scale)
                    .padding(.bottom, 42 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }
}

private struct CleanupJunkSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbolName: String
    let isWide: Bool
    let isPrimary: Bool

    static func makeSummaries(from snapshot: CareScanSnapshot) -> [CleanupJunkSummary] {
        let systemItems = snapshot.cacheDetails.filter { item in
            item.kind == "Browser Cache"
                || item.kind == "App Cache"
                || item.kind == "System Cache"
                || item.kind == "Log File"
                || item.kind == "Temporary File"
                || item.kind == "Package Cache"
        }
        let developerItems = snapshot.cacheDetails.filter { $0.kind == "Developer Cache" }
        let trashItems = snapshot.cacheDetails.filter { $0.kind == "Trash Item" }

        let systemBytes = systemItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let developerBytes = developerItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let trashBytes = trashItems.reduce(Int64(0)) { $0 + $1.sizeBytes }

        let primaryTitle: String
        let primarySubtitle: String

        if systemBytes > 0 {
            primaryTitle = "\(format(systemBytes)) of System Junk Found"
            primarySubtitle = "Browser caches, application caches, logs, temporary files, and package caches ready for review."
        } else if snapshot.cacheItems > 0 {
            primaryTitle = "\(snapshot.formattedCacheSize) of Junk Found"
            primarySubtitle = "Review scanned junk categories before cleaning selected files."
        } else {
            primaryTitle = "Your Mac looks clean"
            primarySubtitle = "No removable cache, log, temporary, developer, or Trash items were found."
        }

        let secondary: CleanupJunkSummary
        if developerBytes > 0 {
            secondary = CleanupJunkSummary(
                id: "developer-junk",
                title: "\(format(developerBytes)) of Xcode Junk\nFound",
                subtitle: nil,
                symbolName: "hammer.fill",
                isWide: false,
                isPrimary: false
            )
        } else if trashBytes > 0 {
            secondary = CleanupJunkSummary(
                id: "trash-bins",
                title: "\(format(trashBytes)) in Trash Bins\nFound",
                subtitle: nil,
                symbolName: "trash.fill",
                isWide: false,
                isPrimary: false
            )
        } else {
            secondary = CleanupJunkSummary(
                id: "scan-coverage",
                title: "Browser, app, log,\nand Trash scan",
                subtitle: nil,
                symbolName: "checkmark.shield.fill",
                isWide: false,
                isPrimary: false
            )
        }

        return [
            CleanupJunkSummary(
                id: "system-junk",
                title: primaryTitle,
                subtitle: primarySubtitle,
                symbolName: snapshot.cacheItems > 0 ? "checkmark.circle.fill" : "checkmark.shield.fill",
                isWide: true,
                isPrimary: true
            ),
            secondary
        ]
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct CleanupJunkCard: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isWide: Bool
    let onClean: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0x6E8B55).opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1.2)
                }

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x98E868), Color(hex: 0x2D8B31)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: symbolName)
                    .font(.system(size: 29, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
            }
            .padding(.top, 22)
            .padding(.trailing, 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(isWide ? 1 : 2)
                    .minimumScaleFactor(0.72)
                    .padding(.bottom, subtitle == nil ? 0 : 14)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                HStack(spacing: 10) {
                    Spacer()

                    Button("Review") {}
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .buttonStyle(.plain)
                        .frame(width: 78, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                }
                        }

                    if let onClean {
                        Button("Clean", action: onClean)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x143214))
                            .buttonStyle(.plain)
                            .frame(width: 74, height: 36)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(0.92))
                            }
                    }
                }
            }
            .padding(22)
            .padding(.trailing, isWide ? 88 : 52)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CleanupTopBar: View {
    let title: String
    let showsStartOver: Bool
    let onStartOver: () -> Void

    var body: some View {
        HStack {
            if showsStartOver {
                Button(action: onStartOver) {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))

                        Text("Start Over")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button("Unlock Full Version") {}
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.9))
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0xFFE16A))
                        .shadow(color: Color(hex: 0xFFE16A).opacity(0.18), radius: 12, y: 5)
                }
        }
        .frame(height: 48)
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CleanupCircleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x8FD66F).opacity(0.24))
                    .blur(radius: 18)
                    .scaleEffect(1.2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x7EBD63),
                                Color(hex: 0x4F7C3B),
                                Color(hex: 0x315F2D)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.78), lineWidth: 2)
                    }
                    .shadow(color: Color(hex: 0x8FD66F).opacity(0.28), radius: 24, y: 9)

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct CleanupCompletePanel: View {
    let cleanedSize: String
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
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }

                CleanupDisk()
                    .frame(width: min(proxy.size.width * 0.46, 390))
                    .offset(x: -proxy.size.width * 0.11, y: -4)

                VStack(alignment: .leading, spacing: 28) {
                    Text("Cleanup complete!")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: 0x7EA6FF),
                                            Color(hex: 0x3420A8)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 46, height: 46)

                            Image(systemName: "trash.fill")
                                .font(.system(size: 21, weight: .bold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.85))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(cleanedSize) of Junk")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("successfully cleaned")
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
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

private struct CleanupDisk: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.28))
                .frame(width: 360, height: 74)
                .blur(radius: 12)
                .offset(y: 126)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xEAF7E7).opacity(0.92),
                            Color(hex: 0x7EE36E).opacity(0.82),
                            Color(hex: 0x176B19),
                            Color(hex: 0x082A0E)
                        ],
                        center: UnitPoint(x: 0.28, y: 0.22),
                        startRadius: 22,
                        endRadius: 205
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.44),
                                    Color(hex: 0x91DD7B).opacity(0.7),
                                    .black.opacity(0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                }
                .shadow(color: .black.opacity(0.38), radius: 12, y: 10)

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 310, height: 310)
                .blur(radius: 5)
                .offset(x: 54, y: -44)
                .clipShape(Circle())

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xF5F7FF).opacity(0.96),
                            Color(hex: 0xC6EBC7).opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 142, height: 142)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 5)

            Circle()
                .fill(Color(hex: 0x7DDA69))
                .frame(width: 34, height: 34)
                .offset(x: 26, y: -48)

            Capsule()
                .fill(Color(hex: 0x4AAD42))
                .frame(width: 34, height: 13)
                .offset(x: 26, y: 46)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct CleanupSidebar: View {
    private let items: [CleanupSidebarItem] = [
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
                CleanupSidebarIcon(item: item)
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

private struct CleanupSidebarIcon: View {
    let item: CleanupSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .cleanup ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .cleanup ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), Color(hex: 0x83F07B).opacity(item == .cleanup ? 0.95 : 0.45))
                .frame(width: 58, height: 58)

            if item == .cleanup {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private enum CleanupSidebarItem: String, Identifiable {
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

private struct CleanupBackground: View {
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
                center: UnitPoint(x: 0.2, y: 0.72),
                startRadius: 18,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.67, y: 0.05),
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
    JunkCleanerView()
        .frame(width: 1180, height: 760)
}
