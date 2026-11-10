import AppKit
import SwiftUI

/// Settings, shown in the main window like the other sections (sidebar footer or ⌘,).
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                SettingsTabBar(selection: $settings.selectedTab)
                    .padding(.bottom, AppTheme.Spacing.xxs)

                switch settings.selectedTab {
                case .general: GeneralSettings(settings: settings, model: model)
                case .menuBar: MenuBarSettings(settings: settings, model: model)
                case .cleanUp: CleanUpSettings(settings: settings)
                case .neverClean: NeverCleanSettings(settings: settings)
                case .largeFiles: LargeFilesSettings(settings: settings)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.m)
            .animation(AppTheme.Motion.quick, value: settings.selectedTab)
        }
    }
}

// MARK: - Building blocks

extension SettingsTab {
    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .cleanUp: "Clean Up"
        case .neverClean: "Never Clean"
        case .largeFiles: "Large Files"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .cleanUp: "trash"
        case .neverClean: "hand.raised"
        case .largeFiles: "doc.on.doc"
        }
    }
}

/// Pill-shaped tabs, in the app's style rather than a toolbar.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                        .font(.system(size: 12.5, weight: selection == tab ? .semibold : .medium))
                        .foregroundStyle(selection == tab ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(AppTheme.Colors.raised)
                                    .shadow(color: AppTheme.Colors.raisedShadow, radius: 3, y: 1)
                                    .overlay(Capsule().strokeBorder(AppTheme.Colors.raisedBorder, lineWidth: 1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(AppTheme.Colors.tile))
    }
}

/// A titled card of settings rows, with an optional note under it.
private struct SettingsCard<Content: View, Trailing: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    var footer: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String, subtitle: String? = nil, footer: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.footer = footer
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            VStack(spacing: 0) {
                CardHeader(title, subtitle: subtitle, symbolName: symbol) { trailing }
                RowDivider(leadingInset: 0)
                content
            }
            .card()

            if let footer {
                Text(footer)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.xxs)
            }
        }
    }
}

/// A label with an explanation on the left, its control on the right.
private struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppTheme.Spacing.m)
            control
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
    }
}

/// Three small windows to pick from: System (half light, half dark), Light and Dark.
private struct AppearancePicker: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            ForEach(AppearanceMode.allCases) { mode in
                let isSelected = selection == mode
                Button {
                    withAnimation(AppTheme.Motion.quick) { selection = mode }
                } label: {
                    VStack(spacing: 5) {
                        AppearancePreview(mode: mode)
                            .frame(width: 72, height: 48)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.raisedBorder,
                                                  lineWidth: isSelected ? 2 : 1)
                            }
                        Text(mode.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) appearance")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// A tiny CachePop window in one appearance. System shows light on the left, dark on the right.
private struct AppearancePreview: View {
    let mode: AppearanceMode

    var body: some View {
        Group {
            switch mode {
            case .light:
                MiniWindow(isDark: false)
            case .dark:
                MiniWindow(isDark: true)
            case .system:
                MiniWindow(isDark: false)
                    .overlay {
                        MiniWindow(isDark: true)
                            .mask(HStack(spacing: 0) { Color.clear; Color.black })
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Sidebar, canvas and one card, in fixed light or dark colours (the preview mustn't follow the
/// app's own appearance).
private struct MiniWindow: View {
    let isDark: Bool

    private func tone(_ light: UInt, _ dark: UInt) -> Color { Color(hex: isDark ? dark : light) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3.5) {
                Capsule().fill(AppTheme.Colors.accent).frame(width: 10, height: 3)
                Capsule().fill(tone(0xC4C8CF, 0x48484C)).frame(width: 10, height: 3)
                Capsule().fill(tone(0xC4C8CF, 0x48484C)).frame(width: 10, height: 3)
            }
            .padding(.top, 8)
            .frame(width: 19, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(tone(0xFFFFFF, 0x000000))

            // The hairline between sidebar and page.
            Rectangle().fill(tone(0xE4E4E2, 0x262626)).frame(width: 1)

            VStack(alignment: .leading, spacing: 3.5) {
                Capsule().fill(tone(0xC4C8CF, 0x55555A)).frame(width: 22, height: 3)
                Capsule().fill(AppTheme.Colors.accent).frame(width: 29, height: 3)
            }
            .padding(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(tone(0xF6F6F5, 0x1C1C1C)))
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(tone(0xFFFFFF, 0x000000))
        }
    }
}

private func chooseFolders(prompt: String, message: String, startingAt folder: URL? = nil) -> [URL] {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.directoryURL = folder
    panel.prompt = prompt
    panel.message = message
    return panel.runModal() == .OK ? panel.urls : []
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let model: AppModel
    private let permissions = PermissionsManager.shared
    @State private var isConfirmingHelperRemoval = false

    var body: some View {
        SettingsCard("Appearance", symbol: "circle.lefthalf.filled") {
            SettingsRow(title: "Light or dark",
                        detail: "System follows your Mac's setting in System Settings › Appearance.") {
                AppearancePicker(selection: $settings.appearance)
            }
        }

        SettingsCard("Startup", symbol: "power",
                     footer: settings.loginItemError) {
            SettingsRow(title: "Open CachePop at login",
                        detail: "Starts hidden in the menu bar after you restart, with low-space alerts running. No window opens.") {
                SettingsSwitch(isOn: $settings.opensAtLogin)
                    .disabled(!settings.canChangeLoginItem)
            }
        }

        SettingsCard("Low-space alerts", symbol: "bell.badge") {
            SettingsRow(title: "Warn when the disk is nearly full",
                        detail: "One notification when free space drops below the level you pick, at most once a day.") {
                SettingsSwitch(isOn: $settings.lowSpaceAlerts)
                    .onChange(of: settings.lowSpaceAlerts) { _, isOn in
                        if isOn { model.requestNotificationPermission() }
                    }
            }
            RowDivider()
            SettingsRow(title: "Warn when free space is") {
                Picker("Warn when free space is", selection: $settings.lowSpaceThreshold) {
                    ForEach(LowSpaceThreshold.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .disabled(!settings.lowSpaceAlerts)
            .opacity(settings.lowSpaceAlerts ? 1 : 0.5)
        }

        SettingsCard("Privacy", symbol: "lock.shield") {
            SettingsRow(title: "Full Disk Access",
                        detail: "Lets CachePop see the Trash, device backups and caches macOS keeps private.") {
                HStack(spacing: AppTheme.Spacing.xs) {
                    // Off limits what Clean Up can see, so it's worth noticing.
                    Pill(text: permissions.hasFullDiskAccess ? "On" : "Off",
                         symbolName: permissions.hasFullDiskAccess ? "checkmark" : "exclamationmark",
                         tone: permissions.hasFullDiskAccess ? .success : .warning)
                    if !permissions.hasFullDiskAccess {
                        Button("Open System Settings…", action: permissions.requestFullDiskAccess)
                    }
                }
            }
        }

        if model.fanControl.status != .notInstalled {
            SettingsCard("Fan control", symbol: "fanblades") {
                SettingsRow(title: "Fan control helper",
                            detail: "Lets CachePop set fan speeds. Removing it hands every fan back to macOS.") {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Pill(text: fanHelperStatus, tone: model.fanControl.status == .ready ? .success : .neutral)
                        Button("Remove…") { isConfirmingHelperRemoval = true }
                    }
                }
            }
            .confirmationDialog("Remove the fan control helper?", isPresented: $isConfirmingHelperRemoval) {
                Button("Remove Helper", role: .destructive) { Task { await model.fanControl.uninstall() } }
            } message: {
                Text("Fans go back to automatic. You can turn fan control on again from System Monitor.")
            }
        }
    }

    private var fanHelperStatus: String {
        switch model.fanControl.status {
        case .ready: "On"
        case .needsApproval: "Waiting for approval"
        case .notInstalled: "Off"
        case .unavailable: "Unavailable"
        }
    }
}

// MARK: - Menu Bar

private struct MenuBarSettings: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    /// A reading has come in and found no fans (MacBook Air), so there's no speed to show.
    private var hasNoFans: Bool { model.monitor.snapshot?.fans.isEmpty == true }

    var body: some View {
        SettingsCard("Menu bar item", symbol: "menubar.rectangle") {
            SettingsRow(title: "Show CachePop in the menu bar",
                        detail: settings.menuBarItemIsRequired
                            ? "Always on while CachePop opens at login: it starts hidden, and this is how you open it."
                            : "Free space, CPU and heat at a glance. CachePop keeps running when its window is closed.") {
                SettingsSwitch(isOn: $settings.showMenuBarItem)
                    .disabled(settings.menuBarItemIsRequired)
            }
        }

        SettingsCard("Readings", symbol: "thermometer.medium") {
            SettingsRow(title: "Show temperature",
                        detail: "The chip's temperature in its own menu bar item. Click it for the CPU, SSD and memory temperatures.") {
                SettingsSwitch(isOn: $settings.menuBarShowsTemperature)
            }
            RowDivider()
            SettingsRow(title: "Show fan speed",
                        detail: hasNoFans ? "This Mac has no fans." : "The fastest fan's speed in its own menu bar item.") {
                SettingsSwitch(isOn: $settings.menuBarShowsFanSpeed)
            }
            .disabled(hasNoFans)
            .opacity(hasNoFans ? 0.5 : 1)
        }
    }
}

// MARK: - Clean Up

private struct CleanUpSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard("What starts ticked", symbol: "checkmark.circle",
                     footer: "Only things that come back on their own or download again start ticked. Big downloads start unticked, so a clean never means a long wait the next time you build.") {
            SettingsRow(title: "Untick downloads that are",
                        detail: "Package caches, simulator runtimes and other things fetched again when needed.") {
                Picker("Untick downloads that are", selection: $settings.redownloadThreshold) {
                    ForEach(RedownloadThreshold.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }

        SettingsCard("Logs", symbol: "doc.text",
                     footer: "Recent logs and crash reports are the ones you'd want when something breaks.") {
            SettingsRow(title: "Keep logs from the last") {
                Picker("Keep logs from the last", selection: $settings.logAgeDays) {
                    Text("Day").tag(1)
                    Text("Week").tag(7)
                    Text("Month").tag(30)
                    Text("3 months").tag(90)
                }
                .labelsHidden()
                .fixedSize()
            }
        }

        SettingsCard("Always, whatever you choose", symbol: "checkmark.shield") {
            promise("lock", "Documents, Photos, Mail, keychains and source code are never touched.")
            RowDivider(leadingInset: 44)
            promise("pause.circle", "Anything in use — a booted simulator, an open app, a running build — is skipped.")
            RowDivider(leadingInset: 44)
            promise("trash", "Files you can see in Finder go to the Trash, so you can put them back.")
        }
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: AppTheme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: AppTheme.Layout.rowIcon)
            Text(text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
    }
}

// MARK: - Never Clean

private struct NeverCleanSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard(
            "Never clean",
            symbol: "hand.raised",
            subtitle: settings.neverClean.isEmpty ? "Nothing listed" : "\(settings.neverClean.count) listed",
            footer: "A listed folder is left alone wherever it appears, including inside caches CachePop clears. To skip an item from a scan, right-click it in Clean Up and choose Always Skip."
        ) {
            Button("Add Folder…", action: addFolders)
        } content: {
            if settings.neverClean.isEmpty {
                Text("Add folders CachePop must leave alone, such as a cache you rely on.")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.m)
            } else {
                ForEach(Array(settings.neverClean.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider(leadingInset: 44) }
                    HStack(spacing: AppTheme.Spacing.s) {
                        if entry.kind == .folder {
                            FinderIcon(path: entry.value, size: AppTheme.Layout.rowIcon)
                        } else {
                            IconTile(symbolName: "hand.raised", size: AppTheme.Layout.rowIcon)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.kind == .folder ? URL(fileURLWithPath: entry.value).lastPathComponent : entry.title)
                                .font(AppTheme.Typography.headline)
                                .lineLimit(1)
                            Text(entry.kind == .folder ? abbreviate(entry.value) : "Skipped in every scan")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: AppTheme.Spacing.s)
                        Button("Remove") {
                            withAnimation(AppTheme.Motion.standard) { settings.remove(entry) }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, 8)
                    .hoverHighlight()
                }
            }
        }
    }

    private func addFolders() {
        let urls = chooseFolders(prompt: "Never Clean", message: "Choose folders CachePop must never clean.",
                                 startingAt: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"))
        for url in urls { settings.neverClean(folder: url) }
    }
}

// MARK: - Large Files

private struct LargeFilesSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard("Size", symbol: "arrow.up.doc",
                     footer: "Duplicates are found from 1 MB, whatever this is set to.") {
            SettingsRow(title: "A file is large when it's over") {
                Picker("A file is large when it's over", selection: $settings.largeFileMinimumMB) {
                    Text("50 MB").tag(50)
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                }
                .labelsHidden()
                .fixedSize()
            }
        }

        SettingsCard(
            "Folders to look in",
            symbol: "folder",
            subtitle: settings.largeFileFolders.isEmpty ? "Your home folders" : "\(settings.largeFileFolders.count) chosen",
            footer: "Source-code projects, build output and the Photos and Music libraries are always skipped."
        ) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if !settings.largeFileFolders.isEmpty {
                    Button("Use Home Folders") { withAnimation { settings.largeFileFolders = [] } }
                }
                Button("Add Folder…", action: addFolders)
            }
        } content: {
            if settings.largeFileFolders.isEmpty {
                HStack(spacing: AppTheme.Spacing.s) {
                    FinderIcon(path: FileManager.default.homeDirectoryForCurrentUser.path, size: AppTheme.Layout.rowIcon)
                    Text("Desktop, Documents, Downloads, Movies, Music and Pictures")
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.vertical, 8)
            } else {
                ForEach(Array(settings.largeFileFolders.enumerated()), id: \.element) { index, path in
                    if index > 0 { RowDivider(leadingInset: 44) }
                    HStack(spacing: AppTheme.Spacing.s) {
                        FinderIcon(path: path, size: AppTheme.Layout.rowIcon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(AppTheme.Typography.headline)
                            Text(abbreviate(path))
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: AppTheme.Spacing.s)
                        Button("Remove") {
                            withAnimation { settings.largeFileFolders.removeAll { $0 == path } }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, AppTheme.Spacing.m)
                    .padding(.vertical, 8)
                    .hoverHighlight()
                }
            }
        }
    }

    private func addFolders() {
        for url in chooseFolders(prompt: "Add", message: "Choose folders to look for large and duplicate files.")
        where !settings.largeFileFolders.contains(url.path) {
            settings.largeFileFolders.append(url.path)
        }
    }
}
