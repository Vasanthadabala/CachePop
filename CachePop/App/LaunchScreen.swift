import SwiftUI

/// A brief brand animation while the main window opens.
struct LaunchScreen: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasTurned = false

    var body: some View {
        ZStack {
            CanvasBackground()

            VStack(spacing: AppTheme.Spacing.m) {
                BrandMark(height: 64)
                    .rotationEffect(.degrees(hasTurned ? 180 : 0))

                Text("CachePop")
                    .font(.system(size: 24, weight: .semibold))
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CachePop is opening")
        .task { await play() }
    }

    private func play() async {
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 0.5)) { hasTurned = true }
            try? await Task.sleep(for: .milliseconds(550))
        }
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

#Preview {
    LaunchScreen(onFinished: {})
        .frame(width: 1000, height: 700)
}
