import SwiftUI

// CachePop's page header: the measuring tape. A small caption, one large light number, and a
// slim ruler in the accent colour with tick marks and end labels. Flat colour only.

extension ByteSize {
    /// "99.93 GB" → ("99.93", "GB"), for a large number with a small unit beside it.
    static func parts(_ bytes: Int64) -> (number: String, unit: String) {
        let pieces = string(bytes).split(separator: " ", maxSplits: 1).map(String.init)
        return (pieces.first ?? "0", pieces.count > 1 ? pieces[1] : "")
    }
}

/// The main action in a header: a solid accent capsule.
struct CapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(AppTheme.Colors.accent))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(AppTheme.Motion.quick, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Tape

/// What a ruler shows: filled stretches (0…1 along it) and the labels under it.
struct Tape {
    struct Segment {
        let from: Double
        let to: Double
        let color: Color
        /// Drawn with thin stripes, for an estimate or a part that's changed.
        var striped = false
    }

    var segments: [Segment]
    var leading: String
    var center: String?
    var trailing: String
    var height: CGFloat = 10
}

/// A slim rounded ruler with tick marks underneath. Fills grow in when it appears.
struct TapeView: View {
    let tape: Tape
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.track)
                    ForEach(Array(tape.segments.enumerated()), id: \.offset) { _, segment in
                        let start = width * min(max(segment.from, 0), 1)
                        let length = max(width * (min(max(segment.to, 0), 1) - min(max(segment.from, 0), 1)), segment.to > segment.from ? 3 : 0)
                        Group {
                            if segment.striped {
                                StripeShape()
                                    .fill(segment.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: tape.height / 2, style: .continuous)
                                    .fill(segment.color)
                            }
                        }
                        .frame(width: grown ? length : 0, height: tape.height)
                        .offset(x: start)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: tape.height)

            HStack(spacing: 0) {
                ForEach(0..<11, id: \.self) { index in
                    Rectangle()
                        .fill(AppTheme.Colors.textTertiary.opacity(0.55))
                        .frame(width: 1, height: index.isMultiple(of: 5) ? 7 : 4)
                    if index < 10 { Spacer(minLength: 0) }
                }
            }
            .frame(height: 7, alignment: .top)

            HStack(spacing: AppTheme.Spacing.s) {
                Text(tape.leading)
                Spacer(minLength: 0)
                if let center = tape.center {
                    Text(center)
                    Spacer(minLength: 0)
                }
                Text(tape.trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.Colors.textTertiary)
            .monospacedDigit()
            .lineLimit(1)
        }
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.easeOut(duration: 0.8).delay(0.1)) { grown = true }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Thin vertical stripes, 3 pt on and 3 pt off.
struct StripeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        while x < rect.maxX {
            path.addRect(CGRect(x: x, y: rect.minY, width: min(3, rect.maxX - x), height: rect.height))
            x += 6
        }
        return path
    }
}

// MARK: - Header

/// The top of a page: caption, one large light number with its unit, an optional sentence,
/// the ruler, and actions — on a single white card.
struct TapeHeader<Actions: View, Accessory: View, Visual: View>: View {
    let caption: String
    let value: String
    let unit: String
    var detail: String?
    var tape: Tape?
    /// Top right, level with the caption: a secondary action such as Scan Again.
    let accessory: Accessory
    /// Under the number, for a picture the plain tape can't show (a breakdown by category).
    let visual: Visual
    let actions: Actions

    init(caption: String, value: String, unit: String, detail: String? = nil, tape: Tape? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder visual: () -> Visual,
         @ViewBuilder actions: () -> Actions) {
        self.caption = caption
        self.value = value
        self.unit = unit
        self.detail = detail
        self.tape = tape
        self.accessory = accessory()
        self.visual = visual()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(caption)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value)
                            .font(.system(size: 48, weight: .light))
                            .tracking(-1.5)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(unit)
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    if let detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                accessory
            }

            if let tape {
                TapeView(tape: tape)
                    .padding(.top, 14)
            }

            visual
                .padding(.top, 14)

            actions
                .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension TapeHeader where Accessory == EmptyView, Visual == EmptyView {
    init(caption: String, value: String, unit: String, detail: String? = nil, tape: Tape? = nil,
         @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.init(caption: caption, value: value, unit: unit, detail: detail, tape: tape,
                  accessory: { EmptyView() }, visual: { EmptyView() }, actions: actions)
    }
}

extension TapeHeader where Actions == EmptyView {
    init(caption: String, value: String, unit: String, detail: String? = nil, tape: Tape? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder visual: () -> Visual) {
        self.init(caption: caption, value: value, unit: unit, detail: detail, tape: tape,
                  accessory: accessory, visual: visual, actions: { EmptyView() })
    }
}

/// The tape header's number on its own: one large light figure with its unit.
struct TapeFigure: View {
    let bytes: Int64
    var unitSuffix = ""

    var body: some View {
        let parts = ByteSize.parts(bytes)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts.number)
                .font(.system(size: 44, weight: .light))
                .tracking(-1.5)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(parts.unit + unitSuffix)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }
}

/// A smaller tape for a row of measurements: caption, number, unit and a slim ruler.
struct TapeStat: View {
    let caption: String
    let value: String
    let unit: String
    let fraction: Double
    let color: Color
    let leading: String
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .light))
                    .tracking(-1)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            TapeView(tape: Tape(segments: [Tape.Segment(from: 0, to: fraction, color: color)],
                                leading: leading, trailing: trailing, height: 6))
                .padding(.top, 8)
                .animation(AppTheme.Motion.standard, value: fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
