import AppKit
import SwiftUI

/// Settings, shown in the main window like the other sections (sidebar footer or ⌘,).
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $settings.selectedTab)
                .padding(.horizontal, AppTheme.Layout.pageGutter)
                .padding(.vertical, AppTheme.Spacing.m)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                    switch settings.selectedTab {
                    case .general: GeneralSettings(settings: settings, model: model)
                    case .menuBar: MenuBarSettings(settings: settings, model: model)
                    case .cleanUp: CleanUpSettings(settings: settings)
                    case .neverClean: NeverCleanSettings(settings: settings)
                    case .largeFiles: LargeFilesSettings(settings: settings)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Layout.pageGutter)
                .padding(.bottom, AppTheme.Spacing.l)
            }
            .id(settings.selectedTab)
        }
        .controlSize(.small)
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
}

/// The tabs across the top of Settings. The selected tab's plate slides to the tab you pick.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab
    @Namespace private var plate
    @State private var hovered: SettingsTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(AppTheme.Motion.quick) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab || hovered == tab ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .padding(.vertical, 6)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(AppTheme.Colors.raised)
                                    .shadow(color: AppTheme.Colors.raisedShadow, radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "plate", in: plate)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(AppTheme.Motion.quick) { hovered = hovering ? tab : (hovered == tab ? nil : hovered) }
                }
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.Colors.tile))
    }
}

/// Settings rows are short, so their cards take a tighter corner than a page's cards.
private enum SettingsCardMetrics {
    static let radius: CGFloat = 10
}

/// A plain section heading above a compact group of preference rows.
private struct SettingsCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppTheme.Spacing.s)
                trailing
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) { content }
                .card(radius: SettingsCardMetrics.radius)
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: AppTheme.Spacing.m)
            control
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

private struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
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
        SettingsCard("General") {
            SettingsRow(title: "Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Open at login") {
                SettingsSwitch(title: "Open CachePop at login", isOn: $settings.opensAtLogin)
                    .disabled(!settings.canChangeLoginItem)
            }
            .help("Start hidden in the menu bar.")
        }

        if let error = settings.loginItemError {
            Text(error)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Status.warning)
                .padding(.horizontal, 6)
        }

        SettingsCard("Low-space alerts") {
            SettingsRow(title: "Low-space alerts") {
                SettingsSwitch(title: "Low-space alerts", isOn: $settings.lowSpaceAlerts)
                    .onChange(of: settings.lowSpaceAlerts) { _, isOn in
                        if isOn { model.requestNotificationPermission() }
                    }
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Free space threshold") {
                Picker("Free space threshold", selection: $settings.lowSpaceThreshold) {
                    ForEach(LowSpaceThreshold.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .disabled(!settings.lowSpaceAlerts)
        }

        SettingsCard("Privacy") {
            SettingsRow(title: "Full Disk Access") {
                HStack(spacing: AppTheme.Spacing.s) {
                    Text(permissions.hasFullDiskAccess ? "On" : "Off")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    if !permissions.hasFullDiskAccess {
                        Button("Open System Settings…", action: permissions.requestFullDiskAccess)
                    }
                }
            }
        }

        if model.fanControl.status != .notInstalled {
            SettingsCard("Fan control") {
                SettingsRow(title: "Fan control helper") {
                    HStack(spacing: AppTheme.Spacing.s) {
                        Text(fanHelperStatus)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
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

    private var hasNoFans: Bool { model.monitor.snapshot?.fans.isEmpty != false }

    var body: some View {
        SettingsCard("Menu Bar") {
            SettingsRow(title: "Show CachePop in the menu bar") {
                SettingsSwitch(title: "Show CachePop in the menu bar", isOn: $settings.showMenuBarItem)
                    .disabled(settings.menuBarItemIsRequired)
            }
            .help(settings.menuBarItemIsRequired ? "Required while Open at login is on." : "Hold ⌘ and drag to rearrange menu bar items.")
        }

        SettingsCard("Readings") {
            SettingsRow(title: hasNoFans ? "Fan speed (unavailable)" : "Fan speed") {
                SettingsSwitch(title: "Show fan speed", isOn: hasNoFans ? .constant(false) : $settings.menuBarShowsFanSpeed)
            }
            .disabled(hasNoFans)
            .opacity(hasNoFans ? 0.4 : 1)
            .help(hasNoFans ? "This Mac has no fans." : "Show the fastest fan's speed.")
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Temperature") {
                SettingsSwitch(title: "Show temperature", isOn: $settings.menuBarShowsTemperature)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "CPU usage") {
                SettingsSwitch(title: "Show CPU usage", isOn: $settings.menuBarShowsCPUUsage)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "GPU usage") {
                SettingsSwitch(title: "Show GPU usage", isOn: $settings.menuBarShowsGPUUsage)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Memory usage") {
                SettingsSwitch(title: "Show memory usage", isOn: $settings.menuBarShowsMemoryUsage)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Drive usage") {
                SettingsSwitch(title: "Show drive usage", isOn: $settings.menuBarShowsSSDUsage)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Battery") {
                SettingsSwitch(title: "Show battery", isOn: $settings.menuBarShowsBattery)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Sensors") {
                SettingsSwitch(title: "Show sensors", isOn: $settings.menuBarShowsSensors)
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Network") {
                SettingsSwitch(title: "Show network traffic", isOn: $settings.menuBarShowsNetwork)
            }
        }

        Text("Hold ⌘ Command and drag a menu bar item to change its position.")
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.horizontal, 6)
    }
}

// MARK: - Clean Up

private struct CleanUpSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard("Clean Up") {
            SettingsRow(title: "Leave downloads unchecked") {
                Picker("Leave downloads unchecked", selection: $settings.redownloadThreshold) {
                    ForEach(RedownloadThreshold.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("redownloadThresholdMenu")
            }
            RowDivider(leadingInset: 10)
            SettingsRow(title: "Keep recent logs") {
                Picker("Keep recent logs", selection: $settings.logAgeDays) {
                    Text("Day").tag(1)
                    Text("Week").tag(7)
                    Text("Month").tag(30)
                    Text("3 months").tag(90)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

// MARK: - Never Clean

private struct NeverCleanSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard("Never Clean") {
            Button("Add Folder…", action: addFolders)
        } content: {
            if settings.neverClean.isEmpty {
                SettingsRow(title: "No folders or items") { EmptyView() }
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                ForEach(Array(settings.neverClean.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider(leadingInset: 10) }
                    SettingsRow(title: entry.kind == .folder ? abbreviate(entry.value) : entry.title) {
                        Button("Remove") {
                            withAnimation(AppTheme.Motion.quick) { settings.remove(entry) }
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.kind == .folder ? entry.value : "Skipped in every scan")
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
        SettingsCard("Large Files") {
            SettingsRow(title: "Minimum size") {
                Picker("Minimum size", selection: $settings.largeFileMinimumMB) {
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

        SettingsCard("Scan folders") {
            HStack(spacing: AppTheme.Spacing.xs) {
                if !settings.largeFileFolders.isEmpty {
                    Button("Use Home Folders") { withAnimation { settings.largeFileFolders = [] } }
                }
                Button("Add Folder…", action: addFolders)
            }
        } content: {
            if settings.largeFileFolders.isEmpty {
                SettingsRow(title: "Home folders") { EmptyView() }
                    .help("Desktop, Documents, Downloads, Movies, Music, Pictures and Public")
            } else {
                ForEach(Array(settings.largeFileFolders.enumerated()), id: \.element) { index, path in
                    if index > 0 { RowDivider(leadingInset: 10) }
                    SettingsRow(title: abbreviate(path)) {
                        Button("Remove") {
                            withAnimation { settings.largeFileFolders.removeAll { $0 == path } }
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
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
