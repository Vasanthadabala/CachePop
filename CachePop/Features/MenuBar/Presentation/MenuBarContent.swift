import AppKit
import SwiftUI

/// Native menu bar images share fixed canvases; only text scales to fit.
enum MenuBarLabel {
    static let glyph: NSImage = {
        let source = NSImage(named: "BrandGlyph") ?? NSImage()
        let height: CGFloat = 16
        let width = source.size.height > 0 ? (source.size.width / source.size.height * height).rounded(.up) : height
        let image = NSImage(size: NSSize(width: 18, height: MenuBarItemLayout.height), flipped: false) { rect in
            source.draw(in: NSRect(x: (rect.width - width) / 2, y: (rect.height - height) / 2, width: width, height: height))
            return true
        }
        image.isTemplate = true
        return image
    }()
}

struct TemperatureStatusReading: View {
    let value: String
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "thermometer.medium").font(.system(size: 13)).frame(width: 9)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.25)
        }.frame(width: MenuBarItemLayout.contentWidth(for: MenuBarItemLayout.compactWidth))
    }
}

enum UsageMenuBarLabel {
    static func image(title: String, value: String, width: CGFloat = MenuBarItemLayout.width) -> NSImage {
        let image = MenuBarItemLayout.image(width: width) {
            VStack(spacing: 0) {
                Text(title).font(.system(size: 7, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.5).frame(height: 8)
                Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.2).frame(width: MenuBarItemLayout.contentWidth(for: width), height: 14)
            }
        }
        image.accessibilityDescription = "\(title) usage, \(value)"
        return image
    }
}

/// The panel that opens from the menu bar: free space, live readings, and a scan.
struct MenuBarContent: View {
    let model: AppModel
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var cleanUp: CleanUpViewModel { model.cleanUp }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack(spacing: AppTheme.Spacing.xs) {
                BrandMark(height: 20)
                    .frame(width: 16)
                Text("CachePop")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    close { model.show(.settings) }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .help("Settings")
            }

            VStack(spacing: 0) {
                MenuBarDiskSummary(disk: model.disk, isLow: model.isLowOnSpace)
                if let snapshot = model.monitor.snapshot {
                    RowDivider(leadingInset: 0)
                    HStack(spacing: AppTheme.Spacing.xs) {
                        MiniStat(symbol: "cpu", value: "\(Int((snapshot.cpu.total * 100).rounded()))%", label: "CPU",
                                 color: Metric.cpu.solid)
                        MiniStat(symbol: "memorychip", value: "\(Int((snapshot.memory.usedFraction * 100).rounded()))%", label: "Memory",
                                 color: Metric.memory.solid)
                        MiniStat(symbol: "thermometer.medium",
                                 value: snapshot.temperatures.chip.map(SystemMonitorViewModel.temperature) ?? "—", label: "Chip",
                                 color: model.monitor.isHot ? AppTheme.Status.warning : Metric.temperature.solid)
                    }
                }
            }
            .card()

            if model.isLowOnSpace {
                InlineNote(text: "Free space is below your alert level.", symbolName: "exclamationmark.triangle", tone: .warning)
            }

            if let status {
                Text(status)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                close(model.scanForJunk)
            } label: {
                Label(primaryTitle, systemImage: primarySymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CapsuleButtonStyle())
            .keyboardShortcut(.defaultAction)

            VStack(spacing: 2) {
                MenuRow(title: "Open CachePop", symbol: "macwindow") { close { model.show(model.section ?? .cleanUp) } }
                MenuRow(title: "System Monitor", symbol: AppSection.systemMonitor.symbolName) { close { model.show(.systemMonitor) } }
                MenuRow(title: "Disk Usage", symbol: AppSection.diskUsage.symbolName) { close { model.show(.diskUsage) } }
                MenuRow(title: "History", symbol: "clock.arrow.circlepath") { close(model.showHistory) }
                Divider().padding(.vertical, 2)
                if model.settings.showsAnyMenuBarItem {
                    MenuRow(title: "Keep Running in Menu Bar", symbol: "menubar.rectangle") {
                        close(model.keepRunningInMenuBar)
                    }
                }
                MenuRow(title: "Quit CachePop", symbol: "power") { model.quitCompletely() }
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(width: 300)
        .onAppear {
            model.refreshDisk()
        }
        .onExitCommand { dismissMenu() }
    }

    private var status: String? {
        switch cleanUp.phase {
        case .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .review where cleanUp.result.reclaimableBytes > 0:
            return "\(ByteSize.string(cleanUp.result.reclaimableBytes)) found, waiting for your review."
        default: return nil
        }
    }

    private var primaryTitle: String {
        switch cleanUp.phase {
        case .review: "Review What Was Found"
        case .scanning, .cleaning: "Show Progress"
        default: "Scan for Junk"
        }
    }

    private var primarySymbol: String {
        cleanUp.phase == .review ? "list.bullet" : "magnifyingglass"
    }

    private func dismissMenu() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func close(_ action: @escaping () -> Void) {
        dismissMenu()
        action()
    }
}

/// A small live figure. Its symbol wears the metric's System Monitor colour.
private struct MiniStat: View {
    let symbol: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Label {
                Text(label)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            .font(AppTheme.Typography.caption)
            .labelStyle(TightLabelStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }
}

/// A row of a menu bar panel's menu: a symbol and a title, with a hover wash.
struct MenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: symbol)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 18)
                Text(title)
            }
            .font(AppTheme.Typography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.xs)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
