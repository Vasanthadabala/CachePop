import AppKit
import SwiftUI

extension PhotoIssue {
    var symbolName: String {
        switch self {
        case .blurry: "camera.aperture"
        case .dark: "moon"
        case .overexposed: "sun.max"
        }
    }
}

extension MemoryPressure {
    @MainActor var color: Color {
        switch self {
        case .normal: AppTheme.Status.success
        case .warning: AppTheme.Status.warning
        case .critical: AppTheme.Palette.red.solid
        }
    }
}

extension MonitorStatus.Level {
    @MainActor var color: Color {
        switch self {
        case .normal: AppTheme.Status.success
        case .warning: AppTheme.Status.warning
        case .unavailable: AppTheme.Colors.textSecondary
        }
    }
}

/// Shared data colors keep each metric consistent between main pages and popup charts.
/// Menu bar labels remain monochrome; gray also identifies inactive and unavailable data.
enum Metric {
    static let cpu = AppTheme.Palette.blue
    static let gpu = AppTheme.Palette.violet
    static let memory = AppTheme.Palette.turquoise
    static let drive = AppTheme.Palette.blue
    static let battery = AppTheme.Palette.green
    static let temperature = AppTheme.Palette.orange
    static let fans = AppTheme.Palette.turquoise
    static let power = AppTheme.Palette.orange
    static let incoming = AppTheme.Palette.blue
    static let outgoing = AppTheme.Palette.red
    static let cpuSystem = AppTheme.Palette.red
    static let idle = Hue(.lightGray)
    // Core types use the turquoise and violet-blue from the reference chart.
    static let efficiency = AppTheme.Palette.turquoise
    static let performance = AppTheme.Palette.violet
    static let wired = AppTheme.Palette.orange
    static let compressed = AppTheme.Palette.violet
    static let cached = Hue(.lightGray)

    static let renderer = AppTheme.Palette.blue
    static let tiler = AppTheme.Palette.turquoise

    static func core(_ kind: CPUCoreKind?) -> Hue {
        switch kind {
        case .efficiency: efficiency
        case .performance: performance
        case nil: cpu
        }
    }

    static func batteryCharge(percent: Int, isCharging: Bool) -> Color {
        if isCharging || percent > 20 { return battery.solid }
        return percent > 10 ? AppTheme.Status.warning : AppTheme.Palette.red.solid
    }
}

/// Shared category colours for the scan ring, results bar and legend.
extension CleanupGroupKind {
    @MainActor var hue: Hue {
        switch self {
        case .xcode: AppTheme.Palette.blue
        case .simulators: AppTheme.Palette.red
        case .browsers: AppTheme.Palette.graphite
        case .developerCaches: AppTheme.Palette.orange
        case .devices: AppTheme.Palette.graphite
        case .general: AppTheme.Palette.green
        case .leftovers: AppTheme.Palette.violet
        }
    }
}

extension SensorGroup {
    @MainActor var hue: Hue {
        switch self {
        case .cpu: Metric.cpu
        case .gpu: Metric.gpu
        case .memory: Metric.memory
        case .drive: Metric.drive
        case .battery: Metric.battery
        case .other: Metric.temperature
        }
    }
}

extension PhotoIssue {
    @MainActor var hue: Hue {
        switch self {
        case .blurry: AppTheme.Palette.turquoise
        case .dark: AppTheme.Palette.violet
        case .overexposed: AppTheme.Palette.orange
        }
    }
}
