import AppKit
import SwiftUI

@MainActor
enum HardwareMenuBarLabel {
    static func sensorsImage() -> NSImage {
        MenuBarItemLayout.image(width: MenuBarItemLayout.compactWidth) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 15, weight: .medium))
        }
    }

    static func networkImage(upload: String, download: String) -> NSImage {
        MenuBarItemLayout.image(width: MenuBarItemLayout.compactWidth) {
            VStack(spacing: 0) {
                networkLine(upload, color: Metric.outgoing.solid)
                networkLine(download, color: Metric.incoming.solid)
            }
        }
    }

    private static func networkLine(_ value: String, color: Color) -> some View {
        let parts = value.dropFirst().split(whereSeparator: \.isWhitespace)
        let amount = parts.first.map(String.init) ?? "—"
        let unit = parts.dropFirst().joined(separator: " ")
        return HStack(spacing: 1.5) {
            Image(systemName: value.hasPrefix("↑") ? "arrow.up" : "arrow.down")
                .foregroundStyle(color)
                .font(.system(size: 7, weight: .medium)).frame(width: 6)
            Text(amount)
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(unit)
                .font(.system(size: 7.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.75).frame(width: 18, alignment: .leading)
        }
        .frame(width: MenuBarItemLayout.contentWidth(for: MenuBarItemLayout.compactWidth), height: 9.5)
    }

    static func batteryImage(percent: Int?, isCharging: Bool, isPluggedIn: Bool = false) -> NSImage {
        BatteryMenuBarIcon.image(percent: percent, showsBolt: isCharging || isPluggedIn)
    }
}
