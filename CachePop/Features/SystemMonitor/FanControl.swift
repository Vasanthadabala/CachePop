import AppKit
import Foundation
import Observation
import ServiceManagement

/// Where the fan helper stands.
enum FanHelperStatus: Equatable {
    /// Not installed yet.
    case notInstalled
    /// Installed, waiting for the user to allow it in System Settings › Login Items.
    case needsApproval
    case ready
    /// Can't be used here, with the reason.
    case unavailable(String)
}

/// Installs the helper and sends it fan commands. Swapped for a fake in demo mode and tests.
@MainActor
protocol FanControlling: AnyObject {
    var status: FanHelperStatus { get }
    func install() throws
    func uninstall() async throws
    func openApprovalSettings()
    func setSpeed(fan: Int, rpm: Double) async throws
    func setAutomatic(fan: Int) async throws
    func setAllAutomatic() async throws
    /// Called when the helper stops and starts again while CachePop is connected.
    var onHelperRestarted: () -> Void { get set }
}

struct FanControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Live

/// The real helper: a launchd daemon registered with SMAppService, reached over XPC.
@MainActor
final class LiveFanController: FanControlling {
    private let service = SMAppService.daemon(plistName: FanHelperConstants.plistName)
    private var connection: NSXPCConnection?

    /// The helper and its launchd plist are inside this app.
    static var isEmbedded: Bool {
        let bundle = Bundle.main.bundleURL
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: bundle.appendingPathComponent("Contents/Library/LaunchDaemons/\(FanHelperConstants.plistName)").path)
            && fileManager.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/CachePopFanHelper").path)
    }

    var status: FanHelperStatus {
        switch service.status {
        case .notRegistered: .notInstalled
        case .requiresApproval: .needsApproval
        case .enabled: .ready
        // macOS reports a daemon that was never registered as "not found", so check the bundle
        // to tell "not installed yet" from "really missing".
        case .notFound: Self.isEmbedded ? .notInstalled : .unavailable("The fan helper is missing from this copy of CachePop.")
        @unknown default: .unavailable("macOS reported an unknown helper state.")
        }
    }

    func install() throws {
        do {
            try service.register()
        } catch let error as NSError where error.code == kSMErrorLaunchDeniedByUser {
            // Registered, but the user has to allow it in System Settings first.
            return
        }
    }

    func uninstall() async throws {
        // Straight to the running helper: no point replacing an outdated one first.
        try? await call(replacingOutdated: false) { helper, reply in helper.setAllAutomatic(reply: reply) }
        dropConnection()
        try await service.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setSpeed(fan: Int, rpm: Double) async throws {
        try await call { helper, reply in helper.setFanSpeed(fan, rpm: rpm, reply: reply) }
    }

    func setAutomatic(fan: Int) async throws {
        try await call { helper, reply in helper.setAutomatic(fan, reply: reply) }
    }

    func setAllAutomatic() async throws {
        try await call { helper, reply in helper.setAllAutomatic(reply: reply) }
    }

    /// Sends one request and waits for the helper's reply (an error message, or nil).
    private func call(
        replacingOutdated: Bool = true,
        _ send: @escaping (FanHelperProtocol, @escaping (String?) -> Void) -> Void
    ) async throws {
        guard status == .ready else { throw FanControlError(message: "Fan control isn't turned on yet.") }
        if replacingOutdated { try await replaceOutdatedHelper() }
        try await request { (helper, once: ResumeOnce<Void>) in
            send(helper) { message in
                if let message {
                    once.resume(with: .failure(FanControlError(message: message)))
                } else {
                    once.resume(with: .success(()))
                }
            }
        }
    }

    /// Asks the helper something and waits for its one answer.
    private func request<Value>(_ send: @escaping (FanHelperProtocol, ResumeOnce<Value>) -> Void) async throws -> Value {
        let connection = currentConnection()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(with: .failure(FanControlError(message: "Couldn't reach the fan helper: \(error.localizedDescription)")))
            }
            guard let helper = proxy as? FanHelperProtocol else {
                once.resume(with: .failure(FanControlError(message: "The fan helper didn't answer.")))
                return
            }
            send(helper, once)
        }
    }

    // MARK: Updates

    /// True once this session has seen that the running helper is the one in this copy.
    private var isHelperCurrent = false
    private var helperCheck: Task<Void, Error>?

    /// The helper never exits on its own, so after CachePop is updated the old one keeps running.
    /// Before the first command, ask its version; if it isn't this copy's, register again:
    /// launchd stops the old helper (which hands its fans back) and starts this one.
    private func replaceOutdatedHelper() async throws {
        guard !isHelperCurrent else { return }
        // Commands sent together wait for the same check.
        if let helperCheck { return try await helperCheck.value }
        let check = Task { try await self.checkHelperVersion() }
        helperCheck = check
        defer { helperCheck = nil }
        try await check.value
    }

    private func checkHelperVersion() async throws {
        let running: String? = try? await request { helper, once in
            helper.helperVersion { once.resume(with: .success($0)) }
        }
        // Unreachable: leave it to the command itself to report that, and ask again next time.
        guard let running else { return }
        guard Self.needsReplacing(runningVersion: running) else {
            isHelperCurrent = true
            return
        }

        dropConnection()
        do {
            try await service.unregister()
            try install()
        } catch {
            throw FanControlError(message: "The fan helper couldn't be updated: \(error.localizedDescription)")
        }
        guard status == .ready else {
            throw FanControlError(message: "The fan helper was updated. Allow “CachePop” in System Settings › General › Login Items & Extensions, then try again.")
        }
        isHelperCurrent = true
    }

    /// Whether a running helper reporting `runningVersion` is older or newer than this copy's.
    nonisolated static func needsReplacing(runningVersion: String) -> Bool {
        runningVersion != FanHelperConstants.version
    }

    // MARK: Connection

    /// Called when the helper stops while CachePop is connected (it crashed, or launchd
    /// restarted it). It hands every fan back to macOS as it starts again.
    var onHelperRestarted: () -> Void = {}

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: FanHelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        // Only talk to our own helper, signed by the same team.
        connection.setCodeSigningRequirement(FanHelperConstants.helperRequirement)
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in
            // Only if it's still the current one: a replaced helper's old connection reports in
            // after the new one exists.
            Task { @MainActor in
                if let self, self.connection.map(ObjectIdentifier.init) == id { self.connection = nil }
            }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.onHelperRestarted() }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    /// Closes the connection first, so stopping the helper on purpose doesn't read as a restart.
    private func dropConnection() {
        connection?.invalidate()
        connection = nil
    }
}

/// XPC can call both the error handler and the reply; resume the continuation only once.
private final class ResumeOnce<Value>: @unchecked Sendable {
    private var continuation: CheckedContinuation<Value, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

// MARK: - View model

/// Fan control in System Monitor: Automatic (macOS decides) or a fixed speed per fan.
///
/// Safety: speeds are clamped to the range each fan reports, and fans go back to automatic when
/// the Mac gets hot, when CachePop quits, and (in the helper) when CachePop disconnects.
@Observable
@MainActor
final class FanControlViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case automatic, custom
        var id: String { rawValue }
        var title: String { self == .automatic ? "Automatic" : "Custom" }
    }

    private(set) var status: FanHelperStatus
    private(set) var mode: Mode = .automatic
    /// Chosen speed per fan, in rpm.
    var targets: [Int: Double] = [:]
    private(set) var isWorking = false
    var message: String?

    /// Keeps System Monitor sampling while fans are on a fixed speed, for the heat check.
    var onModeChanged: (Mode) -> Void = { _ in }

    private let controller: any FanControlling

    init(controller: any FanControlling) {
        self.controller = controller
        status = controller.status
        controller.onHelperRestarted = { [weak self] in
            Task { await self?.helperRestarted() }
        }
    }

    var isCustom: Bool { mode == .custom }

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
        isWorking = true
        defer { isWorking = false }
        do {
            for fan in fans {
                let rpm = target(for: fan)
                targets[fan.index] = rpm
                try await controller.setSpeed(fan: fan.index, rpm: rpm)
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
        // Read afresh: if the helper is waiting for approval again (say, after an update), there's
        // nothing to hand back, and a failed attempt would bury the message saying so.
        refreshStatus()
        guard mode == .custom || status == .ready else { return }
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
        guard mode == .custom else { return }
        let tooHot = (temperatures.chipMax ?? 0) >= FanHelperConstants.releaseTemperature
            || thermalState == .serious || thermalState == .critical
        guard tooHot else { return }
        await setAutomatic()
        if !isCustom { message = "Fans went back to automatic because the Mac got hot." }
    }

    /// The helper stopped while connected (it crashed, or launchd restarted it) and handed every
    /// fan back to macOS as it started again. Make sure of it, and show the switch to Automatic.
    func helperRestarted() async {
        refreshStatus()
        guard mode == .custom else { return }
        await setAutomatic()
        if !isCustom { message = "The fan helper restarted, so fans went back to automatic." }
    }

    private func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        onModeChanged(newMode)
    }
}
