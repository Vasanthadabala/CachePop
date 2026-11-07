import AppKit

/// Whether CachePop is light, dark, or follows the Mac. Chosen in Settings › General.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    /// What the app's windows and menu bar panel use; nil follows the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the mode to the whole app at once, so every window and the menu bar panel match.
    @MainActor
    func apply() {
        NSApp?.appearance = nsAppearance
    }
}
