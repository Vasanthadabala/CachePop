import SwiftUI

/// Shown when CachePop opens: the symbol and name are there from the first frame, then the
/// symbol turns half a circle three times and the app opens. The symbol is nearly symmetric,
/// so every half-turn lands on the same shape. With Reduce Motion there's no spin.
struct LaunchScreen: View {
    /// Called once the animation has played, so the app can fade in.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var halfTurns: Double = 0

    static let spins = 3

    var body: some View {
        ZStack {
            CanvasBackground()

            VStack(spacing: AppTheme.Spacing.l) {
                BrandMark(height: 96)
                    .rotationEffect(.degrees(halfTurns * 180))

                Text("CachePop")
                    .font(.system(size: 30, weight: .bold))
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CachePop is opening")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(700))
            onFinished()
            return
        }

        // A beat with the icon at rest, then the turns.
        try? await Task.sleep(for: .milliseconds(400))
        // Each half-turn is unhurried: about a second, settling gently.
        for _ in 0..<Self.spins {
            withAnimation(.spring(response: 0.84, dampingFraction: 0.8)) { halfTurns += 1 }
            try? await Task.sleep(for: .milliseconds(960))
        }

        // Let the last turn settle before the app fades in.
        try? await Task.sleep(for: .milliseconds(300))
        onFinished()
    }
}

#Preview {
    LaunchScreen(onFinished: {})
        .frame(width: 1000, height: 700)
}
