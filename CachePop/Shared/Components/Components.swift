import SwiftUI
import UniformTypeIdentifiers

// The small set of building blocks every screen is made from. If a screen needs something
// that isn't here, add it here rather than styling it inline.

// MARK: - Headers

// MARK: - Motion

/// Cards fade up into place when a screen opens, a beat apart, so the eye follows them in
/// order. Reduce Motion shows them at once.
struct RevealOnAppear: ViewModifier {
    let order: Int
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 5)
            .onAppear {
                guard !isShown else { return }
                if reduceMotion {
                    isShown = true
                } else {
                    withAnimation(.easeOut(duration: 0.18).delay(Double(min(order, 4)) * 0.025)) {
                        isShown = true
                    }
                }
            }
    }
}

extension View {
    func revealOnAppear(_ order: Int = 0) -> some View {
        modifier(RevealOnAppear(order: order))
    }
}

/// The heading row at the top of a card: icon tile, title, subtitle, trailing controls.
struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var symbolName: String?
    /// Only when the card is one of several categories told apart by colour.
    var hue: Hue?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, symbolName: String? = nil, hue: Hue? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.hue = hue
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            if let symbolName {
                IconTile(symbolName: symbolName, hue: hue)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTheme.Typography.title2)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppTheme.Spacing.s)
            trailing.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 10)
    }
}

// MARK: - Icons

/// A symbol in a soft rounded square. Neutral by default; accent only for the active thing.
struct IconTile: View {
    enum Tone { case neutral, accent, success, warning }

    let symbolName: String
    var size: CGFloat = 28
    var tone: Tone = .neutral
    /// A category glyph on a soft tint, shared with its chart and legend.
    var hue: Hue?

    private var foreground: Color {
        switch tone {
        case .neutral: AppTheme.Colors.textSecondary
        case .accent:  AppTheme.Colors.accent
        case .success: AppTheme.Status.success
        case .warning: AppTheme.Status.warning
        }
    }

    private var fill: Color {
        switch tone {
        case .neutral: AppTheme.Colors.tile
        case .accent:  AppTheme.Colors.accentSoft
        case .success: AppTheme.Status.successSoft
        case .warning: AppTheme.Status.warningSoft
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        if let hue {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(hue.solid)
                .frame(width: size, height: size)
                .background(shape.fill(hue.wash))
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(shape.fill(fill))
        }
    }
}

/// A file or app icon from Finder, at a fixed size.
struct FinderIcon: View {
    let path: String
    var size: CGFloat = 28
    var fallback: UTType = .item
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: fallback == .applicationBundle ? "app" : "doc")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(path)|\(size)|\(fallback.identifier)") {
            image = nil
            let loaded = await IconCache.load(forFile: path, points: size, fallback: fallback)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .onDisappear { image = nil }
    }
}

// MARK: - Pills and notes

/// A small capsule label. Neutral unless it reports a state: green when all is well, orange
/// when something needs care.
struct Pill: View {
    enum Tone { case neutral, success, warning }

    let text: String
    var symbolName: String?
    var tone: Tone = .neutral
    var symbolColor: Color?

    private var foreground: Color {
        switch tone {
        case .neutral: AppTheme.Colors.textSecondary
        case .success: AppTheme.Status.success
        case .warning: AppTheme.Status.warning
        }
    }

    private var fill: Color {
        switch tone {
        case .neutral: AppTheme.Colors.tile
        case .success: AppTheme.Status.successSoft
        case .warning: AppTheme.Status.warningSoft
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(symbolColor ?? foreground)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
        .fixedSize()
    }
}

/// Whether data comes back once removed, as a pill. Only "Doesn't come back" is coloured.
struct RegenerationTag: View {
    let regeneration: Regeneration

    var body: some View {
        Pill(text: regeneration.label, symbolName: regeneration.symbolName, tone: regeneration.isLossy ? .warning : .neutral)
    }
}

/// Icon and caption-sized text, closer together than the default label.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

/// A single-line note under a row: a caution, or why something is skipped.
struct InlineNote: View {
    enum Tone { case neutral, warning }

    let text: String
    var symbolName = "info.circle"
    var tone: Tone = .neutral

    var body: some View {
        Label(text, systemImage: symbolName)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(tone == .warning ? AppTheme.Status.warning : AppTheme.Colors.textSecondary)
            .labelStyle(TightLabelStyle())
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Selection

enum SelectionState {
    case off, on, mixed
}

/// CachePop's checkbox: a rounded square that fills with the accent when ticked, with a
/// "mixed" state for select-all on a group.
struct SelectionBox: View {
    let state: SelectionState
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(state == .off ? AppTheme.Colors.raised : AppTheme.Colors.accent)
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(state == .off ? AppTheme.Colors.textTertiary.opacity(0.7) : .clear, lineWidth: 1.2)
                if state != .off {
                    Image(systemName: state == .on ? "checkmark" : "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .animation(AppTheme.Motion.quick, value: state)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityAddTraits(state == .on ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(state == .on ? "Selected" : state == .mixed ? "Partly selected" : "Not selected")
    }
}

// MARK: - Figures

/// A byte count, right-aligned in lists. "Up to" marks sizes that can overcount shared storage.
struct SizeText: View {
    let bytes: Int64
    var isUpperBound = false
    var emphasized = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if isUpperBound {
                Text("up to")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
            }
            Text(ByteSize.string(bytes))
                .font(AppTheme.Typography.size)
                .foregroundStyle(emphasized ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A big byte figure split into number and unit, e.g. "18.3" + "GB".
struct FigureText: View {
    let bytes: Int64
    var font: Font = AppTheme.Typography.display

    var body: some View {
        let parts = ByteSize.string(bytes).split(separator: " ", maxSplits: 1).map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts.first ?? "0")
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText())
            if parts.count > 1 {
                Text(parts[1])
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Breakdown

/// One part of a breakdown bar, in its category colour.
struct BreakdownSegment: Identifiable {
    let id: String
    let title: String
    let color: Color
    let total: Int64
    let selected: Int64
}

/// Keeps tiny categories visible without making the whole bar wider than its container.
nonisolated enum BreakdownGeometry {
    static func widths(for bytes: [Int64], availableWidth: CGFloat, gap: CGFloat = 3) -> [CGFloat] {
        guard !bytes.isEmpty else { return [] }
        let width = max(availableWidth - gap * CGFloat(bytes.count - 1), 0)
        let minimum = min(6, width / CGFloat(bytes.count))
        let remainder = max(width - minimum * CGFloat(bytes.count), 0)
        let total = bytes.reduce(0.0) { $0 + Double(max($1, 0)) }
        return bytes.map { minimum + (total > 0 ? remainder * CGFloat(Double(max($0, 0)) / total) : remainder / CGFloat(bytes.count)) }
    }
}

/// What was found, by category: each segment's width is its share, its colour where selected
/// and plain track where not.
struct BreakdownBar: View {
    let segments: [BreakdownSegment]
    var showsUnselectedColors = false

    var body: some View {
        GeometryReader { proxy in
            let visible = segments.filter { $0.total > 0 }
            let widths = BreakdownGeometry.widths(for: visible.map(\.total), availableWidth: proxy.size.width)
            HStack(spacing: 3) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, segment in
                    let segmentWidth = widths[index]
                    let selectedFraction = segment.total > 0 ? min(max(Double(segment.selected) / Double(segment.total), 0), 1) : 0
                    ZStack(alignment: .leading) {
                        Rectangle().fill(showsUnselectedColors ? segment.color.opacity(0.25) : AppTheme.Colors.track)
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: segmentWidth * CGFloat(selectedFraction))
                    }
                    .frame(width: segmentWidth)
                    .animation(AppTheme.Motion.standard, value: selectedFraction)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// A legend entry for the breakdown bar.
struct LegendItem: View {
    let segment: BreakdownSegment

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(segment.color)
                .frame(width: 10, height: 10)
            Text(segment.title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text(ByteSize.string(segment.total))
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .fixedSize()
    }
}

// MARK: - Bars and banners

/// The floating glass bar at the bottom of a review list: what's selected, and the primary action.
struct FloatingActionBar<Actions: View>: View {
    let summary: String
    var detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content fades out under the bar instead of showing in a hard strip below it.
            LinearGradient(
                colors: [AppTheme.Colors.canvas.opacity(0), AppTheme.Colors.canvas.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 84)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            bar
        }
    }

    private var bar: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(AppTheme.Typography.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: AppTheme.Spacing.m)
            actions.fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, AppTheme.Spacing.l)
        .padding(.trailing, AppTheme.Spacing.s)
        .padding(.vertical, AppTheme.Spacing.s)
        .card(radius: AppTheme.Radius.bar, raised: true)
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.m)
    }
}

/// A calm, full-width notice with an optional action.
struct NoticeBanner: View {
    enum Tone { case info, success, warning }

    let text: String
    var tone: Tone = .info
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var symbol: String {
        switch tone {
        case .info:    "info"
        case .success: "checkmark"
        case .warning: "exclamationmark"
        }
    }

    private var tileTone: IconTile.Tone {
        switch tone {
        case .info:    .neutral
        case .success: .success
        case .warning: .warning
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.s) {
            IconTile(symbolName: symbol, size: 22, tone: tileTone)
            Text(text)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppTheme.Spacing.xs)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .card(padding: AppTheme.Spacing.s, radius: AppTheme.Radius.medium + 2)
    }
}

// MARK: - States

/// Centred progress for scanning and cleaning.
struct ProgressPanel: View {
    let title: String
    var detail: String?
    /// nil shows an indeterminate circular arc.
    var progress: Double?
    var cancelTitle = "Stop"
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.l) {
            ProgressRing(progress: progress)

            VStack(spacing: 6) {
                Text(title)
                    .font(AppTheme.Typography.title)
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(detail)
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 440)
                        .contentTransition(.opacity)
                }
            }

            if let onCancel {
                Button(cancelTitle, action: onCancel)
                    .secondaryAction()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The same ring for measured progress and scans whose total is not known yet.
private struct ProgressRing: View {
    let progress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(AppTheme.Colors.track, lineWidth: 5)
            if let progress {
                let fraction = min(max(progress, 0), 1)
                Circle()
                    .trim(from: 0, to: max(fraction, 0.02))
                    .stroke(AppTheme.Colors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(AppTheme.Motion.standard, value: fraction)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(AppTheme.Colors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(reduceMotion ? -90 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360 - 90))
                }
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(progress.map { "\(Int(min(max($0, 0), 1) * 100)) percent" } ?? "In progress")
    }
}

/// Shown when a list has nothing in it.
struct EmptyStateView<Actions: View>: View {
    let symbolName: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(symbolName: String, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.s) {
            IconTile(symbolName: symbolName, size: 44)
                .padding(.bottom, AppTheme.Spacing.xs)
            Text(title)
                .font(AppTheme.Typography.title2)
            Text(message)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            actions
                .padding(.top, AppTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xl)
    }
}

/// Hairline between rows inside a card, inset to line up with row text.
struct RowDivider: View {
    var leadingInset: CGFloat = AppTheme.Spacing.m

    var body: some View {
        Rectangle()
            .fill(AppTheme.Colors.separator)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Hover

private struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? AppTheme.Colors.hover : .clear)
            .onHover { hovering in
                withAnimation(AppTheme.Motion.quick) { isHovered = hovering }
            }
    }
}

extension View {
    /// A faint wash behind a row while the pointer is over it.
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }

    /// Scroll content that ends above the floating action bar.
    func clearsActionBar() -> some View {
        padding(.bottom, AppTheme.Layout.actionBarClearance)
    }
}

extension NSWorkspace {
    func revealInFinder(_ path: String) {
        selectFile(path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Layout

/// Lays children out left to right and wraps to a new line when they don't fit, like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Charts

/// A small line chart of recent values, newest on the right.
struct Sparkline: View {
    let values: [Double]
    var minimum: Double = 0
    /// nil scales to the largest value shown.
    var maximum: Double?
    var color: Color
    var capacity = SystemMonitorViewModel.historyLength
    var showsBackground = true

    var body: some View {
        GeometryReader { proxy in
            let points = SparklineGeometry.points(values, minimum: minimum, maximum: maximum, capacity: capacity, in: proxy.size)
            ZStack {
                if let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.21), color.opacity(0.025)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: first)
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .background(showsBackground ? AppTheme.Colors.tile.opacity(0.5) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

/// Two series on one shared scale, e.g. read and write.
struct DualSparkline: View {
    let first: [Double]
    let second: [Double]
    let firstColor: Color
    let secondColor: Color

    var body: some View {
        let top = max((first + second).max() ?? 0, 1)
        ZStack {
            Sparkline(values: first, maximum: top, color: firstColor)
            Sparkline(values: second, maximum: top, color: secondColor, showsBackground: false)
        }
    }
}

enum SparklineGeometry {
    /// Points for `values`, right-aligned so the chart fills in from the right as samples arrive.
    static func points(_ values: [Double], minimum: Double, maximum: Double?, capacity: Int, in size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0 else { return [] }
        let top = max(maximum ?? values.max() ?? 1, minimum + 0.0001)
        let step = size.width / CGFloat(max(capacity - 1, 1))
        let start = size.width - step * CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let fraction = min(max((value - minimum) / (top - minimum), 0), 1)
            return CGPoint(x: start + step * CGFloat(index), y: size.height - 2 - (size.height - 4) * CGFloat(fraction))
        }
    }
}
