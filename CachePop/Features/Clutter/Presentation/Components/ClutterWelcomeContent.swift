import AppKit
import SwiftUI

struct ClutterWelcomeContent: View {
    @Binding var selectedFolder: URL
    let onScan: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.Colors.appBackground
                .ignoresSafeArea()

            FeatureIntroScreen(
                symbolName: "folder.fill",
                title: "Clutter",
                subtitle: "Sort through a folder to find the large files and duplicates quietly taking up your disk.",
                points: [
                    FeatureIntroPoint(
                        symbolName: "doc.fill",
                        title: "Large Files",
                        subtitle: "Anything over 100 MB"
                    ),
                    FeatureIntroPoint(
                        symbolName: "doc.on.doc.fill",
                        title: "Duplicates",
                        subtitle: "Matched by content, not just by name"
                    )
                ],
                actionTitle: "Scan Folder",
                action: onScan
            ) {
                VStack(spacing: 10) {
                    Text("FOLDER TO SCAN")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.Colors.textTertiary)

                    ClutterFolderPicker(selectedFolder: $selectedFolder)
                }
                .padding(.bottom, 26)
            }
            .padding(.top, 52)

            Button("Unlock Full Version") {}
                .buttonStyle(.appInteractive)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.inverseText)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background {
                    Capsule(style: .continuous)
                        .fill(FeatureAccent.dashboard.gradient)
                }
                .accentGlow(.dashboard, radius: 12, y: 5)
                .raisedButtonChrome(cornerRadius: 21)
                .padding(.top, 28)
                .padding(.trailing, 28)
        }
        .background(AppTheme.Colors.appBackground)
    }
}

struct ClutterFolderHero: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Ellipse()
                    .fill(FeatureAccent.clutter.solid.opacity(0.18))
                    .frame(width: size * 0.82, height: size * 0.16)
                    .blur(radius: 18)
                    .offset(y: size * 0.32)

                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(FeatureAccent.clutter.tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1.5)
                    }
                    .frame(width: size * 0.88, height: size * 0.66)
                    .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)

                FolderGlyph()
                    .frame(width: size * 0.70, height: size * 0.52)
                    .accentGlow(.clutter, radius: 20, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FolderGlyph: View {
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
                .fill(FeatureAccent.clutter.gradient)

                Capsule(style: .continuous)
                    .fill(FeatureAccent.clutter.solid.opacity(0.5))
                    .frame(width: w * 0.26, height: h * 0.1)
                    .offset(x: -w * 0.13, y: -h * 0.17)
            }
        }
    }
}

struct ClutterWelcomeFeature: View {
    let symbolName: String
    let title: String

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(FeatureAccent.clutter.solid)
                .frame(width: 34, height: 34)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

struct ClutterFolderPicker: View {
    @Binding var selectedFolder: URL

    private var displayName: String {
        selectedFolder.lastPathComponent.isEmpty ? selectedFolder.path : selectedFolder.lastPathComponent
    }

    var body: some View {
        Button(action: chooseFolder) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .frame(width: 32, height: 25)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.inverseText)
                }

                Text(displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.inverseText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 18)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.inverseText.opacity(0.9))
            }
        }
        .buttonStyle(.appInteractive)
        .padding(.horizontal, 14)
        .frame(width: 305, height: 54)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FeatureAccent.clutter.gradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
        }
        .raisedButtonChrome(cornerRadius: 14)
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
