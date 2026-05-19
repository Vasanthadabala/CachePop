import SwiftUI

struct CareHomeContent: View {
    let scanPhase: ScanPhase
    let scanProgress: Double
    let pulse: Bool
    let scale: CGFloat
    let onScan: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: 70)

                ComputerScanHero()
                .frame(width: 520 * scale, height: 360 * scale)

                VStack(spacing: 16) {
                    Text("Welcome to CachePop")
                        .font(.system(size: 42 * scale, weight: .light, design: .rounded))
                        .foregroundStyle(CachePopPalette.heading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(subtitle)
                        .font(.system(size: 17 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(CachePopPalette.headingMuted)
                        .contentTransition(.numericText())

                    ScanButton(
                        scanPhase: scanPhase,
                        progress: scanProgress,
                        pulse: pulse,
                        action: onScan
                    )
                    .frame(width: 86 * scale, height: 86 * scale)
                    .padding(.top, 8 * scale)
                }
                .padding(.top, 12)

                Spacer(minLength: 74)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("by CachePop")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CachePopPalette.headingMuted.opacity(0.72))
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
        case .readyToRun:
            "Your tasks are ready to run."
        case .cleaning:
            "Cleaning selected tasks..."
        case .complete:
            "Your Mac is in great shape."
        }
    }
}

private struct ComputerScanHero: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

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

                Image("CachePop")
                    .resizable()
                    .scaledToFit()
                    .frame(width: width * 0.72, height: height * 0.72)
                    .shadow(color: Color(hex: 0x6F8DFF).opacity(0.32), radius: 28, y: 16)
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
