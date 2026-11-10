import AppKit
import SwiftUI

/// The menu bar item's icon: CachePop's symbol as a template image. It also hands the app
/// model SwiftUI's window actions, since it stays alive while the main window is closed.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.glyph)
            .accessibilityLabel("CachePop")
            .onAppear {
                model.openMainWindow = { openWindow(id: CachePopApp.mainWindowID) }
            }
    }

    static let glyph: NSImage = {
        let source = NSImage(named: "BrandGlyph") ?? NSImage()
        let height: CGFloat = 16
        let width = source.size.height > 0 ? (source.size.width / source.size.height * height).rounded(.up) : height
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// A live reading in a menu bar item of its own, e.g. "🌡 41°C" or a fan and "1840 rpm".
/// While it shows, System Monitor keeps sampling for it, even with no window open.
struct MenuBarReadingLabel: View {
    enum Reading {
        case temperature, fanSpeed

        var symbolName: String { self == .temperature ? "thermometer.medium" : "fan" }
        var title: String { self == .temperature ? "Chip temperature" : "Fan speed" }
    }

    let model: AppModel
    let reading: Reading
    @Environment(\.openWindow) private var openWindow

    private var value: String {
        let snapshot = model.monitor.snapshot
        let text = reading == .temperature
            ? SystemMonitorViewModel.menuBarTemperature(snapshot)
            : SystemMonitorViewModel.menuBarFanSpeed(snapshot)
        return text ?? "—"
    }

    var body: some View {
        let value = value
        HStack(spacing: 3) {
            Image(systemName: reading.symbolName)
            Text(value)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.title), \(value)")
        .onAppear {
            // CachePop's own icon may be hidden: this item can open the window too.
            model.openMainWindow = { openWindow(id: CachePopApp.mainWindowID) }
        }
        .task {
            model.monitor.begin(SystemMonitorViewModel.menuBarClient)
            defer { model.monitor.end(SystemMonitorViewModel.menuBarClient) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

/// The panel that opens from the menu bar: free space, live readings, and a scan.
struct MenuBarContent: View {
    let model: AppModel
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
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            MenuBarDiskSummary(disk: model.disk, isLow: model.isLowOnSpace)

            if let snapshot = model.monitor.snapshot {
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
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)

            VStack(spacing: 2) {
                MenuRow(title: "Open CachePop", symbol: "macwindow") { close { model.show(model.section ?? .cleanUp) } }
                MenuRow(title: "System Monitor", symbol: AppSection.systemMonitor.symbolName) { close { model.show(.systemMonitor) } }
                MenuRow(title: "Disk Usage", symbol: AppSection.diskUsage.symbolName) { close { model.show(.diskUsage) } }
                MenuRow(title: "History", symbol: "clock.arrow.circlepath") { close(model.showHistory) }
                Divider().padding(.vertical, 2)
                MenuRow(title: "Quit CachePop", symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(width: 300)
        .onAppear {
            model.refreshDisk()
            model.monitor.begin("menu")
        }
        .onDisappear { model.monitor.end("menu") }
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

    private func close(_ action: @escaping () -> Void) {
        dismiss()
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
