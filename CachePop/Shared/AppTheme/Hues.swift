import SwiftUI

// Which category colour each section and Clean Up group wears. Kept in the UI layer so the
// cleanup engine stays free of presentation. See `AppTheme.Palette` for where colour is used.

extension AppSection {
    /// The section's icon colour in the sidebar.
    var hue: Hue {
        switch self {
        case .cleanUp:       AppTheme.Palette.blue
        case .largeFiles:    AppTheme.Palette.sky
        case .photos:        AppTheme.Palette.violet
        case .systemMonitor: AppTheme.Palette.green
        case .diskUsage:     AppTheme.Palette.rose
        case .apps:          AppTheme.Palette.teal
        case .loginItems:    AppTheme.Palette.graphite
        case .settings:      AppTheme.Palette.graphite
        }
    }
}

extension CleanupGroupKind {
    /// One colour per category, shared by the scan, the breakdown bar and the group headers.
    var hue: Hue {
        switch self {
        case .xcode:           AppTheme.Palette.blue
        case .simulators:      AppTheme.Palette.sky
        case .developerCaches: AppTheme.Palette.teal
        case .devices:         AppTheme.Palette.green
        case .leftovers:       AppTheme.Palette.graphite
        case .general:         AppTheme.Palette.rose
        case .browsers:        AppTheme.Palette.violet
        }
    }
}

/// One colour per System Monitor measurement, the same in its header stat, its card's chart and
/// the menu bar panel, so a glance matches them. Incoming and outgoing share one pair across
/// Disk and Network.
enum Metric {
    static let cpu = AppTheme.Palette.blue
    static let memory = AppTheme.Palette.teal
    static let temperature = AppTheme.Palette.rose
    static let fans = AppTheme.Palette.sky
    static let incoming = AppTheme.Palette.blue
    static let outgoing = AppTheme.Palette.teal
}
