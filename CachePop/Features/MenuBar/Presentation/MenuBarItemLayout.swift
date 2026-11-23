import AppKit
import SwiftUI

/// Status buttons reserve their entire width, including the native side insets.
/// Values can change their font size, but never the position of neighboring buttons.
@MainActor
enum MenuBarItemLayout {
    nonisolated static let width: CGFloat = 70
    nonisolated static let compactWidth: CGFloat = width * 0.8
    nonisolated static let batteryScale: CGFloat = 0.8 * 1.05 * 1.05
    nonisolated static let batteryWidth: CGFloat = width * 0.6 * batteryScale * 1.05
    nonisolated static let brandWidth: CGFloat = width / 2
    nonisolated static let contentWidth: CGFloat = width - 8
    nonisolated static let height: CGFloat = 22
    nonisolated static func contentWidth(for width: CGFloat) -> CGFloat { width - 8 }
    /// AppKit adds a one-point outer inset on either side of the status item's length.
    nonisolated static func nativeLength(for width: CGFloat) -> CGFloat { width - 2 }

    static func image<Content: View>(width: CGFloat = MenuBarItemLayout.width, @ViewBuilder content: () -> Content) -> NSImage {
        let contentWidth = Self.contentWidth(for: width)
        let renderer = ImageRenderer(content: content()
            .foregroundStyle(.white)
            .frame(width: contentWidth, height: height))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: contentWidth, height: height))
        image.isTemplate = false
        return image
    }

    /// The fan uses AppKit text alongside its animated rotor.
    static func fittedFontSize(_ value: String, preferred: CGFloat, width: CGFloat) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: preferred, weight: .regular)
        let natural = (value as NSString).size(withAttributes: [.font: font]).width
        guard natural > width, natural > 0 else { return preferred }
        return max(1, preferred * width / natural)
    }
}

enum StatusMenuKind: Hashable {
    case cachePop, temperature, usage(UsageMenuKind)

    static var all: [Self] { [.cachePop, .temperature] + UsageMenuKind.allCases.map { .usage($0) } }
    var rawValue: String {
        switch self { case .cachePop: "cachePop"; case .temperature: "temperature"; case .usage(let kind): kind.rawValue }
    }
    var title: String {
        switch self { case .cachePop: "CachePop"; case .temperature: "Temperature"; case .usage(let kind): kind.title }
    }
    var shortcut: String {
        switch self { case .cachePop: "p"; case .temperature: "t"; case .usage(let kind): kind.shortcut }
    }
    var setting: ReferenceWritableKeyPath<AppSettings, Bool> {
        switch self { case .cachePop: \.showMenuBarItem; case .temperature: \.menuBarShowsTemperature; case .usage(let kind): kind.setting }
    }
    var backgroundClient: String? {
        switch self { case .cachePop: nil; case .temperature: "sensorMenuBar"; case .usage(let kind): kind.backgroundClient }
    }
    var client: String {
        switch self { case .cachePop: "menu"; case .temperature: "temperatureMenu"; case .usage(let kind): kind.client }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .cachePop: "cachePopMenuBarItem"
        case .temperature: "temperatureMenuBarItem"
        case .usage(let kind): "\(kind.rawValue)UsageMenuBarItem"
        }
    }
    @MainActor var width: CGFloat {
        switch self {
        case .cachePop: MenuBarItemLayout.brandWidth
        case .temperature, .usage(.cpu), .usage(.gpu), .usage(.memory), .usage(.drive), .usage(.sensors), .usage(.network): MenuBarItemLayout.compactWidth
        case .usage(.battery): MenuBarItemLayout.batteryWidth
        default: MenuBarItemLayout.width
        }
    }
}
