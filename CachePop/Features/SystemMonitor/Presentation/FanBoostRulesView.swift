import SwiftUI

struct FanBoostRulesView: View {
    @Bindable var control: FanControlViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto Boost Rules").font(.title2.bold())
            Text("Boost all fans when a temperature reaches its threshold. The strongest matching rule wins. Fans return to macOS after temperatures fall 3°C below every active threshold.")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($control.boostRules) { $rule in
                        HStack(spacing: 10) {
                            Toggle("Enabled", isOn: $rule.isEnabled).labelsHidden().toggleStyle(.checkbox)
                            Picker("Sensor", selection: $rule.source) {
                                ForEach(FanBoostRule.Source.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 130)
                            Stepper("\(Int(rule.threshold))°C", value: $rule.threshold, in: 30...90, step: 5)
                                .frame(width: 90)
                            Stepper("\(Int(rule.percent))%", value: $rule.percent, in: 50...100, step: 5)
                                .frame(width: 85)
                            Button { control.boostRules.removeAll { $0.id == rule.id } } label: {
                                Image(systemName: "minus.circle")
                            }.buttonStyle(.plain).accessibilityLabel("Remove boost rule")
                        }
                    }
                }.padding(.vertical, 4)
            }.frame(minHeight: 90, maxHeight: 250)
            Text("Unavailable sensors never trigger a rule. Speeds stay inside each fan's reported limits; heat protection and automatic recovery remain active.")
                .font(AppTheme.Typography.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Add Rule", systemImage: "plus") { control.boostRules.append(FanBoostRule()) }
                    .disabled(control.boostRules.count >= 8)
                Button("Restore Defaults") { control.boostRules = FanBoostRule.defaults }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 550)
    }
}
