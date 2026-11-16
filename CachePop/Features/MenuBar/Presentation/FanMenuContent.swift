import SwiftUI

struct FanMenuContent: View {
    let model: AppModel
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            HStack {
                Text("Fans").font(.system(size: 14, weight: .bold))
                Spacer()
                Pill(text: model.fanControl.mode.title, tone: .neutral)
            }
            if let fans = model.monitor.snapshot?.fans {
                if fans.isEmpty {
                    Text("This Mac has no fans. It uses passive cooling.")
                        .font(AppTheme.Typography.callout)
                } else {
                    ForEach(fans) { fan in
                        HStack(spacing: 10) {
                            FanRotor(rpm: fan.rpm).frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fan \(fan.index + 1)")
                                Text("\(Int(fan.minimum))–\(Int(fan.maximum)) rpm")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Text("\(Int(fan.rpm.rounded()).formatted(.number.grouping(.never))) rpm")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(AppTheme.Motion.standard, value: fan.rpm)
                                .accessibilityIdentifier("fanRPM\(fan.index)")
                        }
                        .font(AppTheme.Typography.body)
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("fanPopupRow\(fan.index)")
                    }
                    Divider()
                    FanControlPanel(control: model.fanControl, fans: fans)
                }
            } else {
                ProgressView("Reading fans…")
            }
            Divider()
            VStack(spacing: 2) {
                MenuRow(title: "System Monitor", symbol: AppSection.systemMonitor.symbolName) {
                    close(); model.show(.systemMonitor)
                }
                MenuRow(title: "Menu Bar Settings", symbol: "menubar.rectangle") {
                    close(); model.settings.selectedTab = .menuBar; model.show(.settings)
                }
                MenuRow(title: "Quit CachePop", symbol: "power") { model.quitCompletely() }
            }
        }
        .padding(AppTheme.Spacing.m)
        .frame(width: 340)
        .onAppear { model.fanControl.refreshStatus(); model.monitor.begin("fanMenu") }
        .onDisappear { model.monitor.end("fanMenu") }
    }
}
