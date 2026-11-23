import AppKit
import SwiftUI

/// Menu bar commands: sections in the View menu (⌘1–⌘5), and a Clean menu.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Commands exist before a restored window appears, including native-menu-only launches.
        let _ = registerWindowAction()
        CommandGroup(replacing: .newItem) {}

        // Settings open in the main window, like the other sections.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            if model.settings.showsAnyMenuBarItem {
                Button("Keep Running in Menu Bar") { model.keepRunningInMenuBar() }
                    .keyboardShortcut("q", modifiers: .command)
                Button("Quit CachePop") { model.quitCompletely() }
                    .keyboardShortcut("q", modifiers: [.command, .option])
            } else {
                Button("Quit CachePop") { model.quitCompletely() }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }

        CommandGroup(before: .sidebar) {
            ForEach(AppSection.navigation) { section in
                Button(section.title) { model.show(section) }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
            }
            Divider()
        }

        CommandMenu("Clean") {
            Button("Scan Again") { model.rescanCurrentSection() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Clean Selected…") {
                model.show(.cleanUp)
                model.cleanUp.requestClean()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(model.cleanUp.phase != .review || model.cleanUp.selections.isEmpty)
            Divider()
            Button("History") { model.showHistory() }
                .keyboardShortcut("y", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Menu("Monitoring Panels") {
                ForEach(StatusMenuKind.all, id: \.self) { kind in
                    Button("\(kind.title) panel") { model.openMenuBarPanel(kind) }
                        .keyboardShortcut(KeyEquivalent(Character(kind.shortcut)), modifiers: [.command, .control])
                        .disabled(!model.settings[keyPath: kind.setting])
                }
            }
        }
    }

    private func registerWindowAction() {
        model.openMainWindow = { [openWindow] in openWindow(id: CachePopApp.mainWindowID) }
    }
}
