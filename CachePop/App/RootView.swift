import AppKit
import SwiftUI

struct RootView: View {
    @State private var model: AppModel

    init(model: AppModel) {
        _model = State(initialValue: model)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            NavigationSplitView {
                AppSidebar(model: model)
                    // The sidebar is the app's navigation, as in System Settings: no toggle.
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                VStack(spacing: 0) {
                    let section = model.section ?? .cleanUp
                    SectionPageBar(model: model, section: section)
                    detail
                        .id(section)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // The bar takes the title-bar row; the window keeps no toolbar of its own.
                .ignoresSafeArea(.container, edges: .top)
                .background(CanvasBackground())
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            }
            .toolbar(removing: .title)

            if model.isLaunching {
                LaunchScreen(onFinished: { model.endLaunch(reduceMotion: reduceMotion) })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .frame(minWidth: 940, minHeight: 640)
        .onAppear {
            model.openMainWindow = { openWindow(id: CachePopApp.mainWindowID) }
            model.refreshDisk()
            model.monitor.begin("window")
        }
        .onDisappear { model.monitor.end("window") }
        .onChange(of: model.settings.appearance) { _, mode in mode.apply() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDisk()
            PermissionsManager.shared.refresh()
            model.fanControl.refreshStatus()
        }
        .task { await model.finishLaunchIfStuck(reduceMotion: reduceMotion) }
        #if DEBUG
        .task { await DemoTour.runIfRequested(model: model) }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section ?? .cleanUp {
        case .cleanUp:
            CleanUpView(model: model.cleanUp, disk: model.disk, history: model.history, isShowingHistory: $model.isShowingHistory)
        case .largeFiles:
            LargeFilesView(model: model.largeFiles)
        case .systemMonitor:
            SystemMonitorView(model: model.monitor, fanControl: model.fanControl, disk: model.disk,
                              onOpenMenuBarSettings: {
                                  model.settings.selectedTab = .menuBar
                                  withAnimation(AppTheme.Motion.standard) { model.section = .settings }
                              }) { section in
                withAnimation(AppTheme.Motion.standard) { model.section = section }
            }
        case .diskUsage:
            DiskUsageView(model: model.diskUsage, disk: model.disk) { section in
                withAnimation(AppTheme.Motion.standard) { model.section = section }
            }
        case .apps:
            AppsView(model: model.apps)
        case .loginItems:
            LoginItemsView(model: model.loginItems)
        case .settings:
            SettingsView(settings: model.settings, model: model)
        }
    }
}

/// The page bar, reading the section's live status itself: a monitor sample or a measured
/// folder then redraws the bar alone, not the whole window and the open section.
private struct SectionPageBar: View {
    let model: AppModel
    let section: AppSection

    var body: some View {
        PageBar(section: section, subtitle: model.pageSubtitle(for: section))
    }
}
