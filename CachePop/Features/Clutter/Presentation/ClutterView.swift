//
//  ClutterView.swift
//  CachePop
//
//  Created by Vasanth on 14/05/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClutterView: View {
    var onBack: () -> Void = {}
    @State private var phase: ClutterViewPhase = .welcome
    @State private var selectedFolder = FileManager.default.homeDirectoryForCurrentUser
    @State private var scannedResult: ClutterScanResult?
    @State private var scanningPath = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var reviewTarget: ClutterReviewTarget = .all
    @State private var scanTask: Task<Void, Never>?
    @State private var duplicateSelectionsByGroupID: [String: Set<String>] = [:]

    var body: some View {
        Group {
            switch phase {
            case .welcome:
                ClutterWelcomeContent(
                    selectedFolder: $selectedFolder,
                    onScan: startScan
                )
            case .scanning:
                ClutterScanningContent(
                    folder: selectedFolder,
                    currentPath: scanningPath,
                    onStop: stopScan
                )
            case .summary:
                ClutterResultsSummaryContent(
                    result: scannedResult ?? .empty,
                    onStartOver: {
                        duplicateSelectionsByGroupID = [:]
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            phase = .welcome
                        }
                    },
                    onReview: { target in
                        reviewTarget = target
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            phase = .manager
                        }
                    }
                )
            case .manager:
                ClutterManagerContent(onBack: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        phase = .summary
                    }
                }, result: scannedResult, reviewTarget: reviewTarget, duplicateSelectionsByGroupID: $duplicateSelectionsByGroupID)
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 10)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func startScan() {
        scanTask?.cancel()
        duplicateSelectionsByGroupID = [:]
        let folderToScan = selectedFolder
        scanningPath = sampleScanningPaths(in: folderToScan).first ?? folderToScan.path

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .scanning
        }

        scanTask = Task {
            let paths = sampleScanningPaths(in: folderToScan)
            let scanWork = Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanClutter(in: folderToScan)
            }

            for path in paths {
                if Task.isCancelled {
                    scanWork.cancel()
                    return
                }

                await MainActor.run {
                    scanningPath = path
                }

                try? await Task.sleep(for: .milliseconds(280))
            }

            let scan = await scanWork.value
            if Task.isCancelled { return }

            await MainActor.run {
                scannedResult = ClutterScanResult(details: scan.details, permissions: scan.permissions)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    phase = .summary
                }
            }
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil

        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            phase = .welcome
        }
    }

    private func sampleScanningPaths(in folder: URL) -> [String] {
        let basePath = folder.path
        return [
            basePath,
            "\(basePath)/Downloads/archive-assets.zip",
            "\(basePath)/AndroidStudioProjects/.../components/CategoryComponent.kt",
            "\(basePath)/Pictures/IMG_2048.heic",
            "\(basePath)/Documents/export-final.mov",
            "\(basePath)/Desktop/old-installer.dmg"
        ]
    }
}

private enum ClutterViewPhase {
    case welcome
    case scanning
    case summary
    case manager
}

private enum ClutterReviewTarget {
    case all
    case duplicatePhotos
    case duplicateOtherFiles
    case largeFiles

    var initialSection: ClutterSection {
        switch self {
        case .all, .largeFiles:
            .largeFiles
        case .duplicatePhotos, .duplicateOtherFiles:
            .duplicates
        }
    }
}

private struct ClutterWelcomeContent: View {
    @Binding var selectedFolder: URL
    let onScan: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let scale = min(width / 930, height / 740)

            ZStack {
                ClutterWelcomeBackground()

                Button("Unlock Full Version") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.92))
                    .padding(.horizontal, 28)
                    .frame(height: 42)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xFFD34F))
                            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
                    }
                    .position(x: width - 120, y: 40)

                HStack(alignment: .center, spacing: max(48, width * 0.08)) {
                    ClutterFolderHero()
                        .frame(width: max(290, min(430, width * 0.42)), height: max(270, min(390, width * 0.38)))
                        .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Clutter")
                            .font(.system(size: max(38, min(54, 54 * scale)), weight: .light, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
                            .padding(.bottom, 22)

                        Text("Sort through your files and reduce the mess in\njust a few clicks.")
                            .font(.system(size: max(18, min(24, 24 * scale)), weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.66))
                            .lineSpacing(4)
                            .padding(.bottom, 48)

                        VStack(alignment: .leading, spacing: 26) {
                            ClutterWelcomeFeature(symbolName: "folder.fill", title: "Large Files")
                            ClutterWelcomeFeature(symbolName: "doc.on.doc.fill", title: "Duplicates")
                        }
                        .padding(.bottom, 64)

                        ClutterFolderPicker(selectedFolder: $selectedFolder)
                    }
                    .frame(width: min(410, width * 0.42), alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, max(44, width * 0.08))
                .padding(.top, 28)
                .padding(.bottom, 92)

                Button(action: onScan) {
                    Text("Scan")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.96))
                        .frame(width: 106, height: 106)
                        .background {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(hex: 0x8EA8FF),
                                            Color(hex: 0x6F7DFF),
                                            Color(hex: 0x4E60D0)
                                        ],
                                        center: .top,
                                        startRadius: 8,
                                        endRadius: 74
                                    )
                                )
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.72), lineWidth: 2)
                                }
                                .shadow(color: Color(hex: 0x86A6FF).opacity(0.55), radius: 38, x: 0, y: 0)
                                .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
                        }
                }
                .buttonStyle(.plain)
                .position(x: width / 2, y: height - 62)
            }
        }
        .background(AppTheme.Colors.appBackground)
    }
}

private struct ClutterScanningContent: View {
    let folder: URL
    let currentPath: String
    let onStop: () -> Void
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let scale = min(width / 930, height / 740)

            ZStack {
                ClutterWelcomeBackground()

                Text("Clutter")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                    .position(x: width / 2, y: 34)

                Button("Unlock Full Version") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.92))
                    .padding(.horizontal, 28)
                    .frame(height: 42)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color(hex: 0xFFD34F))
                            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
                    }
                    .position(x: width - 120, y: 40)

                VStack(spacing: 0) {
                    ClutterFolderHero()
                        .frame(width: max(300, min(400, width * 0.36)), height: max(250, min(350, width * 0.32)))
                        .padding(.bottom, max(30, height * 0.04))

                    Text("Digging through...")
                        .font(.system(size: max(36, min(52, 52 * scale)), weight: .light, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.94))
                        .padding(.bottom, 20)

                    Text(compactPath(currentPath))
                        .font(.system(size: max(16, min(21, 21 * scale)), weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: min(620, width * 0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 26)
                .padding(.bottom, 126)

                Button(action: onStop) {
                    Text("Stop")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.96))
                        .frame(width: 106, height: 106)
                        .background {
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color(hex: 0x8EA8FF),
                                                Color(hex: 0x6F7DFF),
                                                Color(hex: 0x4E60D0)
                                            ],
                                            center: .top,
                                            startRadius: 8,
                                            endRadius: 74
                                        )
                                    )

                                Circle()
                                    .trim(from: 0.08, to: 0.88)
                                    .stroke(Color(hex: 0xDCE4FF).opacity(0.92), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                                    .frame(width: 118, height: 118)
                                    .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: isAnimating)

                                Circle()
                                    .stroke(.white.opacity(0.52), lineWidth: 2)
                            }
                            .shadow(color: Color(hex: 0x86A6FF).opacity(0.52), radius: 38, x: 0, y: 0)
                            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
                        }
                }
                .buttonStyle(.plain)
                .position(x: width / 2, y: height - 62)
            }
        }
        .background(AppTheme.Colors.appBackground)
        .onAppear {
            isAnimating = true
        }
    }

    private func compactPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let resolvedPath = path.hasPrefix(home) ? path.replacingOccurrences(of: home, with: "~") : path

        guard resolvedPath.count > 76 else { return resolvedPath }
        let prefix = resolvedPath.prefix(34)
        let suffix = resolvedPath.suffix(34)
        return "\(prefix)...\(suffix)"
    }
}

private struct ClutterResultsSummaryContent: View {
    let result: ClutterScanResult
    let onStartOver: () -> Void
    let onReview: (ClutterReviewTarget) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack {
                ClutterWelcomeBackground()

                HStack {
                    Button(action: onStartOver) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 17, weight: .bold))
                            Text("Start Over")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Clutter")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))

                    Spacer()

                    Button("Unlock Full Version") {}
                        .buttonStyle(.plain)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.92))
                        .padding(.horizontal, 28)
                        .frame(height: 42)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(hex: 0xFFD34F))
                                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
                        }
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("You have \(result.filesToSortCount) files to sort through.")
                        Text("Use quick recommendations or review them by hand.")
                    }
                    .font(.system(size: max(25, min(33, width * 0.032)), weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
                    .multilineTextAlignment(.center)

                    Button("Review All Files") {
                        onReview(.all)
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                        .frame(width: 154, height: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(.white.opacity(0.18), lineWidth: 1)
                                }
                        }
                }
                .padding(.top, 94)
                .frame(maxHeight: .infinity, alignment: .top)

                HStack(alignment: .bottom, spacing: 20) {
                    ClutterSummaryTallCard(
                        title: "\(result.duplicateOtherFileCount) Duplicate Other Files",
                        subtitle: result.duplicateOtherFileCount == 0
                            ? "No duplicate documents, archives, installers, audio, or video found."
                            : "Review duplicate documents, archives, installers, audio, and video.",
                        fileCount: result.duplicateOtherFileCount,
                        sizeText: result.duplicateOtherSizeText,
                        onReview: { onReview(.duplicateOtherFiles) }
                    )
                    .frame(width: max(280, min(370, width * 0.32)))

                    VStack(spacing: 18) {
                        ClutterSummaryWideCard(
                            title: "\(result.duplicatePhotoFileCount) Duplicate Photos",
                            subtitle: result.duplicatePhotoFileCount == 0
                                ? "No duplicate images found in the scanned folders."
                                : "Remove up to \(result.duplicatePhotoSizeText) of repeated images.",
                            symbolName: "photo.on.rectangle.angled",
                            imageItems: result.duplicatePhotoPreviewItems,
                            onReview: { onReview(.duplicatePhotos) }
                        )

                        ClutterSummaryWideCard(
                            title: "\(result.largeFilesSizeText) of Large Files",
                            subtitle: result.largeFiles.isEmpty
                                ? "No files above 100 MB were found."
                                : "Review large files to save a significant amount of space.",
                            symbolName: "doc.fill",
                            imageItems: Array(result.largeFiles.prefix(3)),
                            onReview: { onReview(.largeFiles) }
                        )
                    }
                }
                .padding(.horizontal, 42)
                .padding(.bottom, 34)
                .padding(.top, 245)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(AppTheme.Colors.appBackground)
    }
}

private struct ClutterSummaryTallCard: View {
    let title: String
    let subtitle: String
    let fileCount: Int
    let sizeText: String
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(fileCount == 0 ? subtitle : "Remove \(sizeText) of duplicate files.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.62))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(alignment: .bottom) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                    .offset(y: -12)

                Image(systemName: "doc.fill")
                    .font(.system(size: 94, weight: .regular))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 7)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
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

private struct ClutterSummaryWideCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let imageItems: [CareScanDetailItem]
    let onReview: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(subtitle)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.62))
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

private struct ClutterSummaryPreviewStrip: View {
    let symbolName: String
    let items: [CareScanDetailItem]

    var body: some View {
        HStack(spacing: 14) {
            if items.isEmpty {
                Image(systemName: symbolName)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))
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
                        .foregroundStyle(Color(hex: 0x6F7DFF))
                }
        }
    }
}

private struct ClutterSummaryReviewButton: View {
    let onReview: () -> Void

    var body: some View {
        Button("Review", action: onReview)
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
            .frame(width: 84, height: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
            }
    }
}

private var summaryCardBackground: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(AppTheme.Colors.appBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Colors.border.opacity(0.7), lineWidth: 1)
        }
}

private struct ClutterWelcomeBackground: View {
    var body: some View {
        AppTheme.Colors.appBackground
            .ignoresSafeArea()
    }
}

private struct ClutterFolderHero: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x8EA8FF).opacity(0.18),
                                Color(hex: 0x312994).opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1.5)
                    }
                    .frame(width: size * 0.74, height: size * 0.54)
                    .shadow(color: Color(hex: 0x6F7DFF).opacity(0.22), radius: 28, x: 0, y: 12)

                Image(systemName: "folder.fill")
                    .font(.system(size: size * 0.46, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: 0x8EA8FF), Color(hex: 0xDCE4FF))
                    .shadow(color: Color(hex: 0x6F7DFF).opacity(0.32), radius: 22, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.28), radius: 16, x: 8, y: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FolderGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack(alignment: .bottomTrailing) {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.03, y: h * 0.28))
                    path.addQuadCurve(to: CGPoint(x: w * 0.26, y: h * 0.08), control: CGPoint(x: w * 0.05, y: h * 0.08))
                    path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.08))
                    path.addQuadCurve(to: CGPoint(x: w * 0.53, y: h * 0.24), control: CGPoint(x: w * 0.49, y: h * 0.08))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.24))
                    path.addQuadCurve(to: CGPoint(x: w * 0.94, y: h * 0.42), control: CGPoint(x: w * 0.91, y: h * 0.24))
                    path.addLine(to: CGPoint(x: w * 0.94, y: h * 0.82))
                    path.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.94), control: CGPoint(x: w * 0.94, y: h * 0.94))
                    path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.94))
                    path.addQuadCurve(to: CGPoint(x: w * 0.02, y: h * 0.82), control: CGPoint(x: w * 0.02, y: h * 0.94))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xEEF2FF),
                            Color(hex: 0x8EA8FF),
                            Color(hex: 0x5366D6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Capsule(style: .continuous)
                    .fill(Color(hex: 0x1C2A68).opacity(0.7))
                    .frame(width: w * 0.26, height: h * 0.1)
                    .offset(x: -w * 0.13, y: -h * 0.17)
            }
        }
    }
}

private struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.32))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.14),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.12),
            control2: CGPoint(x: rect.minX + rect.width * 0.31, y: rect.minY + rect.height * 0.17)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.17),
            control1: CGPoint(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.10),
            control2: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.87, y: rect.minY + rect.height * 0.49),
            control1: CGPoint(x: rect.minX + rect.width * 0.96, y: rect.minY + rect.height * 0.29),
            control2: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.39)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.83),
            control1: CGPoint(x: rect.minX + rect.width * 0.98, y: rect.minY + rect.height * 0.67),
            control2: CGPoint(x: rect.minX + rect.width * 0.77, y: rect.minY + rect.height * 0.80)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.19, y: rect.minY + rect.height * 0.82),
            control1: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.86),
            control2: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.98)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.32),
            control1: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.61),
            control2: CGPoint(x: rect.minX + rect.width * 0.03, y: rect.minY + rect.height * 0.46)
        )
        path.closeSubpath()
        return path
    }
}

private struct ClutterWelcomeFeature: View {
    let symbolName: String
    let title: String

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbolName)
                .font(.system(size: 23, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(hex: 0x8EA8FF), Color(hex: 0xDCE4FF))
                .frame(width: 34, height: 34)

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

private struct ClutterFolderPicker: View {
    @Binding var selectedFolder: URL

    private var displayName: String {
        selectedFolder.lastPathComponent.isEmpty ? selectedFolder.path : selectedFolder.lastPathComponent
    }

    var body: some View {
        Button(action: chooseFolder) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: 0x6F7DFF))
                        .frame(width: 32, height: 25)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0xDCE4FF))
                }

                Text(displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 18)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(width: 305, height: 54)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = selectedFolder
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
        }
    }
}

struct ClutterManagerContent: View {
    let onBack: () -> Void
    let snapshot: CareScanSnapshot?
    private let result: ClutterScanResult?
    private let reviewTarget: ClutterReviewTarget
    @Binding private var duplicateSelectionsByGroupID: [String: Set<String>]

    init(onBack: @escaping () -> Void = {}, snapshot: CareScanSnapshot? = nil) {
        self.onBack = onBack
        self.snapshot = snapshot
        self.result = nil
        self.reviewTarget = .all
        self._duplicateSelectionsByGroupID = .constant([:])
    }

    fileprivate init(
        onBack: @escaping () -> Void = {},
        result: ClutterScanResult?,
        reviewTarget: ClutterReviewTarget = .all,
        duplicateSelectionsByGroupID: Binding<[String: Set<String>]> = .constant([:])
    ) {
        self.onBack = onBack
        self.snapshot = nil
        self.result = result
        self.reviewTarget = reviewTarget
        self._duplicateSelectionsByGroupID = duplicateSelectionsByGroupID
    }

    var body: some View {
        MyClutterManager(
            onBack: onBack,
            initialResult: (result ?? snapshot.map {
                ClutterScanResult(
                    details: $0.clutterDetails,
                    permissions: $0.permissionMessages
                )
            })?.filtered(for: reviewTarget),
            initialReviewTarget: reviewTarget,
            duplicateSelectionsByGroupID: $duplicateSelectionsByGroupID
        )
    }
}

private struct MyClutterManager: View {
    let onBack: () -> Void
    let initialResult: ClutterScanResult?
    let initialReviewTarget: ClutterReviewTarget
    @Binding var duplicateSelectionsByGroupID: [String: Set<String>]
    @State private var selectedSection: ClutterSection = .largeFiles
    @State private var selectedItemID: String?
    @State private var isScanning = true
    @State private var scanResult = ClutterScanResult.empty
    @State private var scanTask: Task<Void, Never>?

    private var selectedItem: CareScanDetailItem? {
        scanResult.items(for: selectedSection).first { $0.id == selectedItemID }
            ?? scanResult.items(for: selectedSection).first
    }

    private var relatedItems: [CareScanDetailItem] {
        guard let selectedItem else { return [] }
        return scanResult.relatedItems(for: selectedItem, in: selectedSection)
    }

    var body: some View {
        ZStack {
            ClutterWelcomeBackground()

            VStack(spacing: 0) {
                MyClutterToolbar(onBack: onBack)

                HStack(spacing: 0) {
                    MyClutterCategories(
                        selectedSection: selectedSection,
                        result: scanResult
                    ) { section in
                        selectedSection = section
                        selectedItemID = scanResult.items(for: section).first?.id
                    }
                        .frame(width: 252)

                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1)

                    ClutterFilesPane(
                        section: selectedSection,
                        items: scanResult.items(for: selectedSection),
                        permissions: scanResult.permissions,
                        duplicateCounts: scanResult.duplicateCountByRepresentativeID,
                        selectedItemID: $selectedItemID,
                        isScanning: isScanning
                    )
                        .frame(width: 284)

                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 1)

                    ClutterPreviewPane(
                        item: selectedItem,
                        relatedItems: relatedItems,
                        section: selectedSection,
                        duplicateSelectionsByGroupID: $duplicateSelectionsByGroupID
                    )
                }

                MyClutterBottomBar(result: scanResult)
            }
        }
        .background(AppTheme.Colors.appBackground)
        .onAppear {
            applyInitialResultIfNeeded()
        }
        .task {
            startScan()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func startScan() {
        guard initialResult == nil, scanTask == nil else { return }

        scanTask = Task {
            let scan = await Task.detached(priority: .userInitiated) {
                CareSystemScanner.scanClutter()
            }.value

            if Task.isCancelled { return }

            await MainActor.run {
                let result = ClutterScanResult(details: scan.details, permissions: scan.permissions)
                scanResult = result
                selectedSection = .largeFiles
                selectedItemID = result.largeFiles.first?.id ?? result.duplicates.first?.id
                isScanning = false
            }
        }
    }

    private func applyInitialResultIfNeeded() {
        guard let initialResult, isScanning else { return }

        scanResult = initialResult
        let preferredSection = initialReviewTarget.initialSection
        selectedSection = initialResult.items(for: preferredSection).isEmpty
            ? (initialResult.largeFiles.isEmpty && !initialResult.duplicates.isEmpty ? .duplicates : .largeFiles)
            : preferredSection
        selectedItemID = scanResult.items(for: selectedSection).first?.id
        isScanning = false
    }
}

private struct MyClutterToolbar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6F7DFF))

                    Text("Back")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Clutter Manager")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))

            Spacer()

            HStack(spacing: 28) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x6F7DFF))

                HStack(spacing: 6) {
                    Text("Sort by:")
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))

                    Text("Size")
                        .foregroundStyle(Color(hex: 0x6F7DFF))

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6F7DFF))
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 22)
        .background(AppTheme.Colors.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct MyClutterCategories: View {
    let selectedSection: ClutterSection
    let result: ClutterScanResult
    let onSelect: (ClutterSection) -> Void

    private var visibleSections: [ClutterSection] {
        let sections = ClutterSection.allCases.filter { !result.items(for: $0).isEmpty }
        return sections.isEmpty ? [selectedSection] : sections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(visibleSections) { section in
                Button {
                    onSelect(section)
                } label: {
                    HStack {
                        Text(section.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        Spacer()

                        Text("\(result.items(for: section).count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedSection == section ? AppTheme.Colors.textPrimary : AppTheme.Colors.textPrimary.opacity(0.46))
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedSection == section ? AppTheme.Colors.textPrimary.opacity(0.96) : AppTheme.Colors.textPrimary.opacity(0.6))
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.16), lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 42)
        .background(AppTheme.Colors.appBackground)
    }
}

private struct ClutterFilesPane: View {
    let section: ClutterSection
    let items: [CareScanDetailItem]
    let permissions: [String]
    let duplicateCounts: [String: Int]
    @Binding var selectedItemID: String?
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.94))
                .padding(.bottom, 12)

            Text(section.description)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.56))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            HStack(spacing: 6) {
                Text("Show:")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.72))

                Text("All Files")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8EA8FF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
            }
            .padding(.bottom, 30)

            if isScanning {
                ClutterEmptyState(title: "Scanning files...", subtitle: "Checking large files and comparing duplicate file contents.")
            } else if items.isEmpty {
                ClutterEmptyState(title: "Nothing found", subtitle: section.emptyMessage)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                selectedItemID = item.id
                            } label: {
                                ClutterFileRow(
                                    item: item,
                                    section: section,
                                    duplicateTotal: section == .duplicates ? duplicateCounts[item.id, default: 2] : nil,
                                    isSelected: selectedItemID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }

            if !permissions.isEmpty {
                Text(permissions[0])
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.46))
                    .lineLimit(3)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

}

private struct ClutterEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .opacity(title.hasPrefix("Scanning") ? 1 : 0)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.86))

            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.52))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

private struct ClutterFileRow: View {
    let item: CareScanDetailItem
    let section: ClutterSection
    let duplicateTotal: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ClutterFileIcon(item: item, section: section)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                    .lineLimit(1)

                Text(item.formattedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.5))
            }

            Spacer()

            if let duplicateTotal {
                Text("\(duplicateTotal)")
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(minWidth: 42, minHeight: 28)
                    .background(Color(hex: 0x5366D6))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: section.symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.15), Color(hex: 0x8EA8FF).opacity(0.14)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }
}

private struct ClutterFileIcon: View {
    let item: CareScanDetailItem
    let section: ClutterSection

    var body: some View {
        ZStack {
            if let image = NSImage(contentsOfFile: item.path), section == .duplicates {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x8EA8FF), Color(hex: 0x312994)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: section.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
            }
        }
    }
}

private struct ClutterPreviewPane: View {
    let item: CareScanDetailItem?
    let relatedItems: [CareScanDetailItem]
    let section: ClutterSection
    @Binding var duplicateSelectionsByGroupID: [String: Set<String>]
    @State private var focusedDuplicateID: String?

    private var duplicateGroupID: String {
        item?.detail ?? relatedItems.first?.detail ?? "duplicate-group-empty"
    }

    private var defaultDuplicateSelection: Set<String> {
        Set(relatedItems.dropFirst().prefix(1).map(\.id))
    }

    private var selectedDuplicateIDs: Binding<Set<String>> {
        Binding(
            get: {
                duplicateSelectionsByGroupID[duplicateGroupID] ?? defaultDuplicateSelection
            },
            set: { newValue in
                duplicateSelectionsByGroupID[duplicateGroupID] = newValue
            }
        )
    }

    private var displayedItem: CareScanDetailItem? {
        guard section == .duplicates else { return item }
        return relatedItems.first { $0.id == focusedDuplicateID } ?? item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(section == .duplicates ? "Select:" : "Source:")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.74))

                    Text(section == .duplicates ? "Smartly" : item?.subtitle ?? "Selected Folder")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x8EA8FF))

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
                    .opacity(section == .duplicates ? 1 : 0)
            }
            .padding(.top, 42)
            .padding(.bottom, 30)

            if let item {
                VStack(alignment: .leading, spacing: 24) {
                    if section == .duplicates {
                        DuplicateRelatedGrid(
                            items: relatedItems,
                            focusedID: focusedDuplicateID,
                            selectedIDs: selectedDuplicateIDs
                        ) { focusedDuplicateID = $0.id
                        }
                        .frame(maxWidth: 470)
                        .frame(height: 290)
                    } else {
                        ClutterLargePreview(item: item, section: section)
                            .frame(width: 270, height: 270)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(displayedItem?.title ?? item.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.92))
                            .lineLimit(2)

                        Text(displayedItem?.path ?? item.path)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.42))
                            .lineLimit(3)

                        FileInfoGrid(item: displayedItem ?? item)
                    }
                    .padding(.leading, 2)
                }
            } else {
                ClutterEmptyState(title: "No selection", subtitle: "Run the scan to populate this folder view.")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            syncDuplicateSelection()
        }
        .onChange(of: item?.id) { _, _ in
            syncDuplicateSelection()
        }
    }

    private func syncDuplicateSelection() {
        guard section == .duplicates else {
            focusedDuplicateID = nil
            return
        }

        let validIDs = Set(relatedItems.map(\.id))
        if focusedDuplicateID.map({ !validIDs.contains($0) }) != false {
            focusedDuplicateID = relatedItems.first?.id
        }

        if let savedSelection = duplicateSelectionsByGroupID[duplicateGroupID] {
            let validSelection = savedSelection.intersection(validIDs)
            duplicateSelectionsByGroupID[duplicateGroupID] = validSelection.isEmpty ? defaultDuplicateSelection : validSelection
        } else {
            duplicateSelectionsByGroupID[duplicateGroupID] = defaultDuplicateSelection
        }
    }
}

private struct DuplicateRelatedGrid: View {
    let items: [CareScanDetailItem]
    let focusedID: String?
    @Binding var selectedIDs: Set<String>
    let onSelect: (CareScanDetailItem) -> Void

    private let tileWidth: CGFloat = 166
    private let tileHeight: CGFloat = 146
    private let columns = [
        GridItem(.fixed(166), spacing: 16),
        GridItem(.fixed(166), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(items) { item in
                    DuplicateSelectablePreview(
                        item: item,
                        isFocused: focusedID == item.id,
                        isChecked: selectedIDs.contains(item.id),
                        onSelect: { onSelect(item) },
                        onToggle: {
                            selectedIDs = [item.id]
                        }
                    )
                    .frame(width: tileWidth, height: tileHeight)
                }
            }
            .padding(.top, 14)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
        }
    }
}

private struct DuplicateSelectablePreview: View {
    let item: CareScanDetailItem
    let isFocused: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                duplicatePreview
                    .frame(width: 166, height: 146)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isFocused ? Color(hex: 0x8EA8FF) : .white.opacity(0.12),
                                lineWidth: isFocused ? 3 : 1
                            )
                    }
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                DuplicateCheckbox(isChecked: isChecked)
            }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(8)
        }
        .frame(width: 166, height: 146)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var duplicatePreview: some View {
        if let image = NSImage(contentsOfFile: item.path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.08)
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8EA8FF))
            }
        }
    }
}

private struct DuplicateCheckbox: View {
    let isChecked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isChecked ? Color(hex: 0x8EA8FF) : .black.opacity(0.48))
            .frame(width: 30, height: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isChecked ? Color(hex: 0xDCE4FF) : .white.opacity(0.36), lineWidth: 2)
            }
            .overlay {
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
            .shadow(color: .black.opacity(isChecked ? 0.18 : 0.1), radius: 4, x: 0, y: 2)
    }
}

private struct ClutterLargePreview: View {
    let item: CareScanDetailItem
    let section: ClutterSection

    var body: some View {
        ZStack {
            if let image = NSImage(contentsOfFile: item.path), section == .duplicates {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x8EA8FF).opacity(0.72), Color(hex: 0x312994).opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: section.symbolName)
                    .font(.system(size: 82, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))
            }
        }
    }
}

private struct FileInfoGrid: View {
    let item: CareScanDetailItem

    private var rows: [(String, String)] {
        [
            ("Modified:", item.modifiedText),
            ("Location:", item.subtitle),
            ("Size:", item.formattedSize),
            ("File type:", fileType)
        ]
    }

    private var fileType: String {
        let ext = URL(fileURLWithPath: item.path).pathExtension
        if ext.isEmpty {
            return item.kind
        }
        return ext.uppercased()
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 14) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.44))
                    Text(row.1)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.86))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

private struct MyClutterBottomBar: View {
    let result: ClutterScanResult

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 12) {
                Text("\(result.selectedCount) Items Selected")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9))

                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 20)

                Text(result.selectedSize)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.52))
            }

            Spacer()

            Button("Remove") {}
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .buttonStyle(.plain)
                .frame(width: 92, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x8EA8FF), Color(hex: 0x5366D6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(AppTheme.Colors.appBackground)
    }
}

private enum ClutterSection: String, CaseIterable, Identifiable {
    case largeFiles
    case duplicates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeFiles:
            "Large Files"
        case .duplicates:
            "Duplicates"
        }
    }

    var description: String {
        switch self {
        case .largeFiles:
            "Files above 100 MB found in the scanned folder."
        case .duplicates:
            "Identical files found inside the scanned folder by comparing file contents."
        }
    }

    var emptyMessage: String {
        switch self {
        case .largeFiles:
            "No files above 100 MB were found in this folder."
        case .duplicates:
            "No identical duplicate files were found in this folder."
        }
    }

    var symbolName: String {
        switch self {
        case .largeFiles:
            "doc.fill"
        case .duplicates:
            "doc.on.doc.fill"
        }
    }
}

private struct ClutterScanResult {
    let largeFiles: [CareScanDetailItem]
    let duplicates: [CareScanDetailItem]
    let duplicateGroups: [ClutterDuplicateGroup]
    let permissions: [String]

    static let empty = ClutterScanResult(details: [], permissions: [])

    init(details: [CareScanDetailItem], permissions: [String]) {
        self.largeFiles = details
            .filter { $0.kind == "Large File" }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        let duplicateItems = details
            .filter { $0.kind == "Duplicate Candidate" }
            .sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }
        self.duplicateGroups = Dictionary(grouping: duplicateItems) { item in
            item.detail.hasPrefix("duplicate-group-") ? item.detail : "\(item.sizeBytes)-\(item.title)"
        }
        .values
        .map { items in
            let sortedItems = items.sorted {
                if $0.sizeBytes == $1.sizeBytes {
                    return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                }
                return $0.sizeBytes > $1.sizeBytes
            }
            return ClutterDuplicateGroup(items: sortedItems)
        }
        .sorted { $0.totalBytes > $1.totalBytes }
        self.duplicates = duplicateGroups.compactMap(\.representative)
        self.permissions = permissions
    }

    var duplicateCountByRepresentativeID: [String: Int] {
        Dictionary(uniqueKeysWithValues: duplicateGroups.compactMap { group in
            guard let representative = group.representative else { return nil }
            return (representative.id, group.items.count)
        })
    }

    var selectedCount: Int {
        largeFiles.count + duplicates.count
    }

    var selectedSize: String {
        let bytes = (largeFiles + duplicates).reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var filesToSortCount: Int {
        largeFiles.count + duplicateGroups.reduce(0) { total, group in
            total + max(group.items.count - 1, 0)
        }
    }

    var duplicatePhotoFileCount: Int {
        duplicatePhotoGroups.reduce(0) { total, group in
            total + max(group.items.count - 1, 0)
        }
    }

    var duplicateOtherFileCount: Int {
        duplicateOtherGroups.reduce(0) { total, group in
            total + max(group.items.count - 1, 0)
        }
    }

    var duplicatePhotoSizeText: String {
        formattedDuplicateSize(for: duplicatePhotoGroups)
    }

    var duplicateOtherSizeText: String {
        formattedDuplicateSize(for: duplicateOtherGroups)
    }

    var largeFilesSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: largeFiles.reduce(Int64(0)) { $0 + $1.sizeBytes },
            countStyle: .file
        )
    }

    var duplicatePhotoPreviewItems: [CareScanDetailItem] {
        duplicatePhotoGroups.flatMap(\.items)
    }

    private var duplicatePhotoGroups: [ClutterDuplicateGroup] {
        duplicateGroups.filter { group in
            guard let representative = group.representative else { return false }
            return Self.isImagePath(representative.path)
        }
    }

    private var duplicateOtherGroups: [ClutterDuplicateGroup] {
        duplicateGroups.filter { group in
            guard let representative = group.representative else { return true }
            return !Self.isImagePath(representative.path)
        }
    }

    private func formattedDuplicateSize(for groups: [ClutterDuplicateGroup]) -> String {
        let bytes = groups.reduce(Int64(0)) { total, group in
            total + group.items.dropFirst().reduce(Int64(0)) { $0 + $1.sizeBytes }
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func isImagePath(_ path: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: fileExtension) else { return false }
        return type.conforms(to: .image)
    }

    func filtered(for target: ClutterReviewTarget) -> ClutterScanResult {
        switch target {
        case .all:
            return self
        case .largeFiles:
            return ClutterScanResult(details: largeFiles, permissions: permissions)
        case .duplicatePhotos:
            return ClutterScanResult(details: duplicatePhotoGroups.flatMap(\.items), permissions: permissions)
        case .duplicateOtherFiles:
            return ClutterScanResult(details: duplicateOtherGroups.flatMap(\.items), permissions: permissions)
        }
    }

    func items(for section: ClutterSection) -> [CareScanDetailItem] {
        switch section {
        case .largeFiles:
            largeFiles
        case .duplicates:
            duplicates
        }
    }

    func relatedItems(for item: CareScanDetailItem, in section: ClutterSection) -> [CareScanDetailItem] {
        guard section == .duplicates else { return [item] }
        return duplicateGroups.first { $0.representative?.id == item.id }?.items ?? [item]
    }
}

private struct ClutterDuplicateGroup {
    let items: [CareScanDetailItem]

    var representative: CareScanDetailItem? {
        items.first
    }

    var totalBytes: Int64 {
        items.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }
}

private struct ThumbnailView: View {
    let kind: ThumbnailKind

    var body: some View {
        switch kind {
        case .oasis:
            OasisPreview()
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        case .zip:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(hex: 0x1B1C24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }

                VStack(spacing: 2) {
                    Image(systemName: "zipper.page")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.55))
                    Text("ZIP")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.42))
                }
            }
        case .people:
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF3C1A4), Color(hex: 0x406D8D)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -8) {
                    Circle().fill(Color(hex: 0x2B2B2F)).frame(width: 16, height: 16)
                    Circle().fill(Color(hex: 0xE7B08D)).frame(width: 17, height: 17)
                }
                .offset(y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }
}

private struct OasisPreview: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xEEF2FF),
                        Color(hex: 0x7D98F6),
                        Color(hex: 0x3320A8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.03, y: proxy.size.height * 0.92))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.46, y: proxy.size.height * 0.48),
                        control1: CGPoint(x: proxy.size.width * 0.17, y: proxy.size.height * 0.68),
                        control2: CGPoint(x: proxy.size.width * 0.27, y: proxy.size.height * 0.5)
                    )
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.97, y: proxy.size.height * 0.86),
                        control1: CGPoint(x: proxy.size.width * 0.66, y: proxy.size.height * 0.46),
                        control2: CGPoint(x: proxy.size.width * 0.78, y: proxy.size.height * 0.78)
                    )
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(Color(hex: 0x241572).opacity(0.8))

                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: proxy.size.width * 0.28, height: proxy.size.width * 0.28)
                    .blur(radius: 2)
                    .offset(x: -proxy.size.width * 0.05, y: -proxy.size.height * 0.05)

                RoundedRectangle(cornerRadius: proxy.size.height * 0.16, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: max(proxy.size.width * 0.03, 2))
                    .frame(width: proxy.size.width * 0.66, height: proxy.size.height * 0.58)
                    .offset(x: -proxy.size.width * 0.14, y: -proxy.size.height * 0.04)

                ForEach(0..<10) { index in
                    Circle()
                        .fill(Color(hex: 0x7896FF).opacity(0.68))
                        .frame(width: max(proxy.size.width * 0.032, 3))
                        .offset(
                            x: CGFloat(index % 5) * proxy.size.width * 0.14 - proxy.size.width * 0.28,
                            y: CGFloat(index / 5) * proxy.size.height * 0.11 + proxy.size.height * 0.23
                        )
                }
            }
        }
    }
}

private struct MyClutterSidebar: View {
    private let items: [MyClutterSidebarItem] = [
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
                MyClutterSidebarIcon(item: item)
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

private struct MyClutterSidebarIcon: View {
    let item: MyClutterSidebarItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(item == .myClutter ? .white.opacity(0.11) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(item == .myClutter ? .white.opacity(0.16) : .clear, lineWidth: 1)
                }
                .frame(width: 58, height: 58)

            Image(systemName: item.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.9), Color(hex: 0x8EA8FF).opacity(item == .myClutter ? 0.95 : 0.46))
                .frame(width: 58, height: 58)

            if item == .myClutter {
                Circle()
                    .fill(.white.opacity(0.78))
                    .frame(width: 16, height: 16)
                    .shadow(color: .white.opacity(0.65), radius: 4)
                    .offset(x: 5, y: -5)
            }
        }
    }
}

private struct MyClutterBackground: View {
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
                center: UnitPoint(x: 0.22, y: 0.42),
                startRadius: 10,
                endRadius: 520
            )

            LinearGradient(
                colors: [.clear, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct DuplicateFile: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let selected: Int
    let total: Int
    let thumbnail: ThumbnailKind
    let isSelected: Bool

    static let samples = [
        DuplicateFile(name: "oasis_.png", size: "1,2 GB", selected: 6, total: 7, thumbnail: .oasis, isSelected: true),
        DuplicateFile(name: "selfie_2024.zip", size: "841 MB", selected: 4, total: 5, thumbnail: .zip, isSelected: false),
        DuplicateFile(name: "wow.png", size: "21,8 MB", selected: 2, total: 3, thumbnail: .oasis, isSelected: false),
        DuplicateFile(name: "selfie_1.jpg", size: "15,3 MB", selected: 3, total: 4, thumbnail: .people, isSelected: false),
        DuplicateFile(name: "love.jpg", size: "1,6 MB", selected: 1, total: 2, thumbnail: .people, isSelected: false)
    ]
}

private enum ThumbnailKind {
    case oasis
    case zip
    case people
}

private enum MyClutterSidebarItem: String, Identifiable {
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

#Preview {
    ClutterView()
        .frame(width: 1180, height: 760)
}
