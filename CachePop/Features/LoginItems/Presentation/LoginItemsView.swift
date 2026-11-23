import SwiftUI
import UniformTypeIdentifiers

struct LoginItemsView: View {
    @Bindable var model: LoginItemsViewModel

    var body: some View {
        ZStack {
            if model.isScanning {
                ProgressPanel(title: "Checking what starts with your Mac…")
            } else if !model.hasScanned {
                LoginItemsStartView(onScan: model.scan)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AppTheme.Motion.quick, value: model.isScanning)
    }

    private var content: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                loginHeader
                    .revealOnAppear(0)

                if let message = model.message {
                    NoticeBanner(text: message, tone: .warning, onDismiss: { model.message = nil })
                }

                if model.items.isEmpty {
                    EmptyStateView(
                        symbolName: "power",
                        title: "Nothing extra starts with your Mac",
                        message: "No third-party launch agents, daemons or login apps were found."
                    )
                    .frame(height: 170)
                    .card()
                } else {
                    agentsSection
                        .revealOnAppear(1)
                    appsSection
                        .revealOnAppear(2)
                        .id("apps")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.m)
        }
        .onChange(of: model.scrollToApps) { _, scroll in
            guard scroll else { return }
            withAnimation { proxy.scrollTo("apps", anchor: .bottom) }
            model.scrollToApps = false
        }
        }
    }

    // MARK: Sections

    private var agentsSection: some View {
        StartupSection(
            title: "Agents",
            symbol: "gearshape.2",
            items: model.agents,
            model: model
        )
    }

    private var appsSection: some View {
        StartupSection(
            title: "Applications",
            symbol: "macwindow",
            items: model.apps,
            model: model
        ) {
            if model.appsAccess == .denied {
                HStack(spacing: AppTheme.Spacing.s) {
                    InlineNote(text: "CachePop needs permission to read and change your Open at Login apps.",
                               symbolName: "exclamationmark.triangle", tone: .warning)
                    Spacer(minLength: AppTheme.Spacing.s)
                    Button("Allow in Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, AppTheme.Spacing.m)
                .padding(.vertical, AppTheme.Spacing.s)
            }
        }
    }
}

private struct LoginItemsStartView: View {
    let onScan: () -> Void

    var body: some View {
        FeatureIntroScreen(
            points: [
                FeatureIntroPoint(symbolName: "macwindow", title: "Login apps", subtitle: "Apps that open automatically when you log in."),
                FeatureIntroPoint(symbolName: "gearshape.2", title: "Launch agents", subtitle: "Optional helpers and updaters that start with your Mac."),
                FeatureIntroPoint(symbolName: "switch.2", title: "Choose what starts", subtitle: "Turn items on or off after reviewing the list. The scan changes nothing."),
                FeatureIntroPoint(symbolName: "shield", title: "Essential helpers stay hidden", subtitle: "On-demand helpers and required app services are left out.")
            ],
            pointsTitle: "What the scan covers"
        ) {
            FeatureIntroHeader(
                section: .loginItems,
                title: "Choose what starts at login",
                detail: "Review the apps and background helpers that open when you sign in."
            ) {
                Button(action: onScan) {
                    Label("Scan Login Items", systemImage: "magnifyingglass")
                }
                .buttonStyle(CapsuleButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Header

private extension LoginItemsView {
    // The summary tape distinguishes agents from applications; section icons stay neutral.
    static let agentsHue = AppTheme.Palette.blue
    static let appsHue = AppTheme.Palette.violet

    var loginHeader: some View {
        let agentsOn = model.agents.filter(\.isOn).count
        let appsOn = model.apps.filter(\.isOn).count
        let off = model.items.count - agentsOn - appsOn
        let total = Double(max(model.items.count, 1))
        let a = Double(agentsOn) / total
        let b = a + Double(appsOn) / total
        return TapeHeader(
            caption: "Starts with your Mac",
            value: "\(model.onCount)",
            unit: model.onCount == 1 ? "starts on its own" : "start on their own",
            detail: "Switch off the helpers and apps you don't need at startup. Login gets quicker and memory is freed. It doesn't free disk space.",
            tape: model.items.isEmpty ? nil : Tape(
                segments: [
                    Tape.Segment(from: 0, to: a, color: Self.agentsHue.solid),
                    Tape.Segment(from: a, to: b, color: Self.appsHue.solid)
                ],
                leading: "\(agentsOn) \(agentsOn == 1 ? "agent" : "agents") on",
                center: "\(appsOn) \(appsOn == 1 ? "app" : "apps") on",
                trailing: "\(off) off"
            ),
            accessory: {
                Button {
                    SystemInfoService.openLoginItemsSettings()
                } label: {
                    Label("Login Items Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }, visual: { EmptyView() }
        )
    }
}

// MARK: - Section

/// One card: a heading, then a row per item with its switch.
private struct StartupSection<Footer: View>: View {
    let title: String
    let symbol: String
    let items: [LoginItem]
    let model: LoginItemsViewModel
    @ViewBuilder var footer: Footer

    init(title: String, symbol: String, items: [LoginItem], model: LoginItemsViewModel,
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.items = items
        self.model = model
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            CardHeader(title, symbolName: symbol) {
                Text("\(items.filter(\.isOn).count) of \(items.count) on")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.Colors.tile))
                    .fixedSize()
            }
            RowDivider(leadingInset: 0)

            if items.isEmpty {
                Text("None found.")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.m)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider(leadingInset: 48) }
                    StartupRow(item: item, isBusy: model.busyIDs.contains(item.id), isLocked: model.isScanning,
                               onSet: { model.set(item, on: $0) })
                }
            }

            footer
        }
        .card()
    }
}

private enum StartupColumns {
    static let type: CGFloat = 168
    static let control: CGFloat = 104
}

// MARK: - Row

private struct StartupRow: View {
    let item: LoginItem
    let isBusy: Bool
    /// A rescan is reading the system; switches wait for it.
    let isLocked: Bool
    let onSet: (Bool) -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.s) {
            // App icons carry their own margins, so they sit a step above the row-icon size.
            StartupIcon(path: item.iconPath, isApp: item.appPath != nil, size: 28)
                .opacity(item.isOn ? 1 : 0.55)

            Text(item.title)
                .font(AppTheme.Typography.headline)
                .foregroundStyle(item.isOn ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(detail)

            Text(item.typeLabel)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: StartupColumns.type, alignment: .leading)

            control
                .frame(width: StartupColumns.control, alignment: .trailing)

            RevealButton(path: item.path)
        }
        .padding(.horizontal, AppTheme.Spacing.m)
        .padding(.vertical, 8)
        .hoverHighlight()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
    }

    private var detail: String {
        switch item.kind {
        case .openAtLogin: abbreviate(item.path)
        default: item.label ?? abbreviate(item.path)
        }
    }

    private var control: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView().controlSize(.mini)
            } else if item.needsAdmin {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .help("Asks for an administrator password")
            }
            Text(item.isOn ? "On" : "Off")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(item.isOn ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary)
                .frame(width: 24, alignment: .trailing)
            Toggle("Start \(item.title) automatically", isOn: Binding(get: { item.isOn }, set: onSet))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(isBusy || isLocked)
                .help(item.isOn ? "Turn off" : "Turn on")
        }
    }
}

/// The owning app's icon, or the plist's. A missing app gets the generic app icon.
private struct StartupIcon: View {
    let path: String
    let isApp: Bool
    let size: CGFloat

    var body: some View {
        FinderIcon(path: path, size: size, fallback: isApp ? .applicationBundle : .propertyList)
    }
}
