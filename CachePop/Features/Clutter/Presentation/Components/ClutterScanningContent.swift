import SwiftUI

struct ClutterScanningContent: View {
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
                AppTheme.Colors.appBackground
                    .ignoresSafeArea()

                Text("Clutter")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.68))
                    .position(x: width / 2, y: 34)

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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                        .frame(width: 94, height: 94)
                        .background {
                            ZStack {
                                Circle()
                                    .fill(
                                        FeatureAccent.clutter.gradient
                                    )

                                Circle()
                                    .trim(from: 0.08, to: 0.88)
                                    .stroke(AppTheme.Colors.border.opacity(0.92), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                                    .frame(width: 106, height: 106)
                                    .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: isAnimating)

                                Circle()
                                    .stroke(.white.opacity(0.52), lineWidth: 2)
                            }
                            .shadow(color: FeatureAccent.clutter.shadow, radius: 38, x: 0, y: 0)
                            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
                        }
                        .raisedCircleButtonChrome()
                }
                .buttonStyle(.appInteractive)
                .position(x: width / 2, y: height - 86)
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
