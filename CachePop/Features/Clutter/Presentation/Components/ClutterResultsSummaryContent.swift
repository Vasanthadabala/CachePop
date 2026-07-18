import SwiftUI

struct ClutterResultsSummaryContent: View {
    let result: ClutterScanResult
    let onStartOver: () -> Void
    let onReview: (ClutterReviewTarget) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack {
                AppTheme.Colors.appBackground
                    .ignoresSafeArea()

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
                    .buttonStyle(.appInteractive)

                    Spacer()

                    Text("Clutter")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))

                    Spacer()

                    Button("Unlock Full Version") {}
                        .buttonStyle(.appInteractive)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                        .padding(.horizontal, 28)
                        .frame(height: 42)
                        .background {
                            Capsule(style: .continuous)
                                .fill(FeatureAccent.clutter.gradient)
                                .shadow(color: FeatureAccent.clutter.shadow, radius: 16, x: 0, y: 8)
                        }
                        .raisedButtonChrome(cornerRadius: 21)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("You have \(result.filesToSortCount) files to sort through.")
                        Text("Use quick recommendations or review them by hand.")
                    }
                    .font(.system(size: max(21, min(28, width * 0.027)), weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.95))
                    .multilineTextAlignment(.center)

                    Button("Review All Files") {
                        onReview(.all)
                    }
                        .buttonStyle(.appInteractive)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                        .frame(width: 154, height: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(FeatureAccent.clutter.gradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(.white.opacity(0.22), lineWidth: 1)
                                }
                        }
                        .raisedButtonChrome(cornerRadius: 13)
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
