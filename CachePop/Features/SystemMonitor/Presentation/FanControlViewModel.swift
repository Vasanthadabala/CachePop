import AppKit
import Foundation
import Observation
import ServiceManagement

/// Fan control in System Monitor: Automatic (macOS decides) or a fixed speed per fan.
///
/// Safety: speeds are clamped to the range each fan reports, and fans go back to automatic when
/// the Mac gets hot, when CachePop quits, and (in the helper) when CachePop disconnects.
@Observable
@MainActor
final class FanControlViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic, custom, autoBoost
        var id: String { rawValue }
        var title: String {
            switch self { case .automatic: "Automatic"; case .custom: "Custom"; case .autoBoost: "Auto Boost" }
        }
    }

    private(set) var status: FanHelperStatus
    private(set) var mode: Mode = .automatic
    /// Chosen speed per fan, in rpm.
    var targets: [Int: Double] = [:]
    private(set) var isWorking = false
    var message: String?
    var boostRules: [FanBoostRule] { didSet { onBoostRulesChanged(boostRules) } }
    var onBoostRulesChanged: ([FanBoostRule]) -> Void = { _ in }
    private(set) var activeBoostPercent: Double?
    private var activeBoostRules: Set<UUID> = []
    private var boostFloor: [Int: Double] = [:]
    private var appliedBoostTargets: [Int: Double] = [:]
    private var latestTemperatures = TemperatureSample()
    private var commandRevision = 0
    @ObservationIgnored private var isReleasingForHeat = false

    /// Keeps System Monitor sampling while fans are on a fixed speed, for the heat check.
    var onModeChanged: (Mode) -> Void = { _ in }

    private let controller: any FanControlling

    init(controller: any FanControlling, boostRules: [FanBoostRule] = FanBoostRule.defaults) {
        self.controller = controller
        self.boostRules = boostRules
        status = controller.status
        controller.onHelperRestarted = { [weak self] in
            Task { await self?.helperRestarted() }
        }
    }

    var isCustom: Bool { mode == .custom }
    var needsMonitoring: Bool { mode != .automatic }

    func receive(_ snapshot: SystemSnapshot, thermalState: ProcessInfo.ThermalState) {
        latestTemperatures = snapshot.temperatures
        guard needsMonitoring else { return }
        Task {
            await checkSafety(temperatures: snapshot.temperatures, thermalState: thermalState)
            guard (snapshot.temperatures.chipMax ?? snapshot.temperatures.chip ?? 0) < FanHelperConstants.releaseTemperature,
                  thermalState != .serious, thermalState != .critical else { return }
            if mode == .autoBoost, !isWorking {
                await evaluateBoost(snapshot.fans, temperatures: snapshot.temperatures)
            }
        }
    }

    func enableAutoBoost(_ fans: [FanSample]) async {
        guard status == .ready, !fans.isEmpty else { return }
        await setAutomatic()
        guard (latestTemperatures.chipMax ?? latestTemperatures.chip ?? 0) < FanHelperConstants.releaseTemperature,
              ProcessInfo.processInfo.thermalState != .serious, ProcessInfo.processInfo.thermalState != .critical else {
            message = "The Mac is hot. Fans stay on automatic."
            return
        }
        boostFloor = Dictionary(uniqueKeysWithValues: fans.map { ($0.index, $0.rpm) })
        setMode(.autoBoost)
        await evaluateBoost(fans, temperatures: latestTemperatures)
    }

    private func evaluateBoost(_ fans: [FanSample], temperatures: TemperatureSample) async {
        guard mode == .autoBoost, status == .ready, !isWorking else { return }
        guard !fans.isEmpty else {
            await setAutomatic()
            if !needsMonitoring { message = "Fan readings became unavailable, so fans went back to automatic." }
            return
        }
        let evaluation = FanBoostEvaluation.evaluate(rules: boostRules, temperatures: temperatures,
                                                     previous: activeBoostRules)
        activeBoostRules = evaluation.active
        activeBoostPercent = evaluation.percent
        guard let percent = evaluation.percent else {
            guard !appliedBoostTargets.isEmpty else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                try await controller.setAllAutomatic()
                appliedBoostTargets = [:]
                boostFloor = [:]
            } catch {
                message = error.localizedDescription
                await setAutomatic()
            }
            return
        }
        if boostFloor.isEmpty { boostFloor = Dictionary(uniqueKeysWithValues: fans.map { ($0.index, $0.rpm) }) }
        let desired = Dictionary(uniqueKeysWithValues: fans.map { fan in
            (fan.index, FanWritePlan.clamp(max(fan.maximum * percent / 100, boostFloor[fan.index] ?? fan.minimum),
                                           minimum: fan.minimum, maximum: fan.maximum))
        })
        guard desired != appliedBoostTargets else { return }
        let revision = commandRevision
        isWorking = true
        defer { if revision == commandRevision { isWorking = false } }
        do {
            for fan in fans {
                guard revision == commandRevision, mode == .autoBoost else { return }
                try await controller.setSpeed(fan: fan.index, rpm: desired[fan.index] ?? fan.minimum)
            }
            guard revision == commandRevision else { return }
            appliedBoostTargets = desired
            message = nil
        } catch {
            message = error.localizedDescription
            await setAutomatic()
        }
    }

    func refreshStatus() {
        status = controller.status
    }

    func install() {
        do {
            try controller.install()
        } catch {
            message = "The fan helper couldn't be installed: \(error.localizedDescription)"
        }
        refreshStatus()
        if status == .needsApproval {
            message = "Allow “CachePop” in System Settings › General › Login Items & Extensions, then come back."
            controller.openApprovalSettings()
        }
    }

    func openApprovalSettings() {
        controller.openApprovalSettings()
    }

    func uninstall() async {
        await setAutomatic()
        do {
            try await controller.uninstall()
            // launchd stops the helper, which hands every fan back as it goes.
            setMode(.automatic)
            message = "The fan helper was removed."
        } catch {
            message = "The fan helper couldn't be removed: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    /// The speed shown on a fan's slider: the chosen one, or its current speed.
    func target(for fan: FanSample) -> Double {
        FanWritePlan.clamp(targets[fan.index] ?? fan.rpm, minimum: fan.minimum, maximum: fan.maximum)
    }

    /// Holds each fan at its chosen speed.
    func apply(_ fans: [FanSample]) async {
        guard status == .ready, !fans.isEmpty else { return }
        commandRevision += 1
        let revision = commandRevision
        isWorking = true
        defer { if revision == commandRevision { isWorking = false } }
        do {
            for fan in fans {
                guard revision == commandRevision else { return }
                let rpm = target(for: fan)
                targets[fan.index] = rpm
                try await controller.setSpeed(fan: fan.index, rpm: rpm)
                guard revision == commandRevision else { return }
                // Custom from the first fan set, so the heat check covers it even if a later
                // fan fails and handing it back fails too.
                setMode(.custom)
            }
            message = nil
        } catch {
            message = error.localizedDescription
            await setAutomatic()
        }
    }

    /// Sets every fan to its maximum speed.
    func applyMaximum(_ fans: [FanSample]) async {
        for fan in fans { targets[fan.index] = fan.maximum }
        await apply(fans)
    }

    /// Hands every fan back to macOS.
    func setAutomatic() async {
        commandRevision += 1
        activeBoostRules = []
        activeBoostPercent = nil
        appliedBoostTargets = [:]
        boostFloor = [:]
        // Read afresh: if the helper is waiting for approval again (say, after an update), there's
        // nothing to hand back, and a failed attempt would bury the message saying so.
        refreshStatus()
        guard needsMonitoring || status == .ready else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await controller.setAllAutomatic()
        } catch {
            message = "Fans couldn't be handed back to macOS: \(error.localizedDescription)"
            // With the helper still installed, fans may still be on a fixed speed: stay on Custom
            // so the heat check keeps running and trying again.
            refreshStatus()
            if status == .ready { return }
        }
        setMode(.automatic)
    }

    /// Called with every System Monitor reading. A hot Mac always gets its fans back.
    func checkSafety(temperatures: TemperatureSample, thermalState: ProcessInfo.ThermalState) async {
        guard needsMonitoring, !isReleasingForHeat else { return }
        let tooHot = (temperatures.chipMax ?? temperatures.chip ?? 0) >= FanHelperConstants.releaseTemperature
            || thermalState == .serious || thermalState == .critical
        guard tooHot else { return }
        // A slow helper must not receive another release request on every live reading.
        isReleasingForHeat = true
        defer { isReleasingForHeat = false }
        await setAutomatic()
        if !needsMonitoring { message = "Fans went back to automatic because the Mac got hot." }
    }

    /// The helper stopped while connected (it crashed, or launchd restarted it) and handed every
    /// fan back to macOS as it started again. Make sure of it, and show the switch to Automatic.
    func helperRestarted() async {
        refreshStatus()
        guard needsMonitoring else { return }
        await setAutomatic()
        if !needsMonitoring { message = "The fan helper restarted, so fans went back to automatic." }
    }

    private func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        onModeChanged(newMode)
    }
}
