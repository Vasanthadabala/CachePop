import SwiftUI

/// A recommendation derived from the machine's real state, not a canned list.
struct AssistantTip: Identifiable {
    enum Severity {
        case critical
        case advisory
        case healthy

        var accent: FeatureAccent {
            switch self {
            case .critical:  .clutter
            case .advisory:  .boost
            case .healthy:   .cleanup
            }
        }
    }

    enum Action {
        case openBatterySettings
        case openStorageSettings
        case goToFeature(CareSidebarItem)
        case none
    }

    let id = UUID()
    let severity: Severity
    let symbolName: String
    let title: String
    let body: String
    let actionTitle: String?
    let action: Action
}

@Observable
@MainActor
final class AssistantViewModel {
    var snapshot: SystemSnapshot = .empty
    var isLoading = true

    private var refreshTask: Task<Void, Never>?

    func load() {
        refreshTask?.cancel()
        refreshTask = Task {
            let result = await SystemInfoService.snapshot()
            guard !Task.isCancelled else { return }
            self.snapshot = result
            self.isLoading = false
        }
    }

    func cancel() {
        refreshTask?.cancel()
    }

    /// 0–1 overall health, averaged across the signals we can actually measure.
    var healthScore: Double {
        var scores: [Double] = []

        if snapshot.disk.totalBytes > 0 {
            scores.append(max(0, min(1, 1 - snapshot.disk.usedFraction)))
        }

        if snapshot.memory.totalBytes > 0 {
            scores.append(max(0, min(1, 1 - snapshot.memory.usedFraction)))
        }

        if snapshot.battery.isPresent, snapshot.battery.healthPercent > 0 {
            scores.append(Double(snapshot.battery.healthPercent) / 100)
        }

        // Uptime: full marks under a week, tapering to zero at a month.
        let uptimePenalty = min(Double(snapshot.daysSinceRestart) / 30, 1)
        scores.append(1 - uptimePenalty)

        guard !scores.isEmpty else { return 0 }
        return min(scores.reduce(0, +) / Double(scores.count), 1)
    }

    var healthStatus: HealthStatus {
        if isLoading { return .unknown }
        return healthScore >= 0.7 ? .good : .attention
    }

    var healthHeadline: String {
        if isLoading { return "Checking your Mac…" }
        switch healthStatus {
        case .good:      return "Your Mac is running well"
        case .attention: return "Your Mac needs attention"
        case .unknown:   return "Checking your Mac…"
        }
    }

    var healthSubtitle: String {
        if isLoading { return "Reading live system information." }

        let issues = tips.filter { $0.severity != .healthy }.count
        if issues == 0 {
            return "Everything looks healthy right now. Nothing needs your attention."
        }
        return issues == 1
            ? "One thing is worth looking at below."
            : "\(issues) things are worth looking at below."
    }

    /// Tips generated from the live snapshot — only real, currently-true conditions.
    var tips: [AssistantTip] {
        guard !isLoading else { return [] }

        var result: [AssistantTip] = []

        if snapshot.battery.isPresent {
            if snapshot.battery.needsAttention {
                result.append(AssistantTip(
                    severity: .critical,
                    symbolName: "battery.25",
                    title: "Battery health is \(snapshot.battery.healthPercent)%",
                    body: "Your battery holds \(snapshot.battery.healthPercent)% of its original capacity after \(snapshot.battery.cycleCount) cycles. Below 80%, Apple recommends a service check.",
                    actionTitle: "Open Battery Settings",
                    action: .openBatterySettings
                ))
            } else if snapshot.battery.healthPercent > 0 {
                result.append(AssistantTip(
                    severity: .healthy,
                    symbolName: "battery.100.bolt",
                    title: "Battery health is \(snapshot.battery.healthLabel.lowercased())",
                    body: "Holding \(snapshot.battery.healthPercent)% of its original capacity after \(snapshot.battery.cycleCount) cycles.",
                    actionTitle: nil,
                    action: .none
                ))
            }
        }

        if snapshot.disk.isLow {
            result.append(AssistantTip(
                severity: .critical,
                symbolName: "internaldrive.fill",
                title: "Storage is almost full",
                body: "Only \(snapshot.disk.formattedAvailable) free of \(snapshot.disk.formattedTotal). macOS slows down and apps can fail to save when space runs out.",
                actionTitle: "Clean Junk Files",
                action: .goToFeature(.cleanup)
            ))
        } else if snapshot.disk.totalBytes > 0 {
            result.append(AssistantTip(
                severity: .healthy,
                symbolName: "internaldrive",
                title: "\(snapshot.disk.formattedAvailable) of storage free",
                body: "You're using \(Int(snapshot.disk.usedFraction * 100))% of \(snapshot.disk.formattedTotal). There's comfortable headroom.",
                actionTitle: "Find Large Files",
                action: .goToFeature(.myClutter)
            ))
        }

        if snapshot.needsRestart {
            result.append(AssistantTip(
                severity: .advisory,
                symbolName: "power",
                title: "Up for \(snapshot.uptimeText)",
                body: "It's been \(snapshot.uptimeText) since your last restart. Restarting clears caches and frees memory that builds up over time.",
                actionTitle: nil,
                action: .none
            ))
        }

        if snapshot.memory.isUnderPressure {
            result.append(AssistantTip(
                severity: .advisory,
                symbolName: "memorychip.fill",
                title: "Memory is under pressure",
                body: "\(snapshot.memory.formattedUsed) of \(snapshot.memory.formattedTotal) is in use. Quitting background apps will give your Mac more room.",
                actionTitle: "Review Background Items",
                action: .goToFeature(.performance)
            ))
        }

        // Sort so the things that matter surface first.
        return result.sorted { lhs, rhs in
            severityRank(lhs.severity) < severityRank(rhs.severity)
        }
    }

    private func severityRank(_ severity: AssistantTip.Severity) -> Int {
        switch severity {
        case .critical: 0
        case .advisory: 1
        case .healthy:  2
        }
    }

    func perform(_ action: AssistantTip.Action, navigate: (CareSidebarItem) -> Void) {
        switch action {
        case .openBatterySettings:
            SystemInfoService.openBatterySettings()
        case .openStorageSettings:
            SystemInfoService.openStorageSettings()
        case .goToFeature(let item):
            navigate(item)
        case .none:
            break
        }
    }
}
