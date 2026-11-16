import AppKit
import Foundation

@MainActor
protocol DesktopInteracting {
    func chooseFolder(startingAt url: URL, message: String) -> URL?
    func open(_ url: URL)
}

@MainActor
struct MacDesktopInteraction: DesktopInteracting {
    func chooseFolder(startingAt url: URL, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = "Choose"
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
