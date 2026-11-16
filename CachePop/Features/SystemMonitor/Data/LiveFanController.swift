import AppKit
import Foundation
import ServiceManagement

/// The real helper: a launchd daemon registered with SMAppService, reached over XPC.
@MainActor
final class LiveFanController: FanControlling {
    private let service = SMAppService.daemon(plistName: FanHelperConstants.plistName)
    private var connection: NSXPCConnection?

    isolated deinit {
        helperCheck?.cancel()
        connection?.invalidate()
    }

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
            // A connected but unresponsive helper may never invoke either reply
            // callback. Bound the wait and disconnect so its fail-safe releases fans.
            let timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if once.resume(with: .failure(FanControlError(message: "The fan helper took too long to respond."))),
                   self?.connection === connection {
                    self?.dropConnection()
                }
            }
            once.installTimeout(timeout)
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
nonisolated final class ResumeOnce<Value>: @unchecked Sendable {
    private var continuation: CheckedContinuation<Value, Error>?
    private let lock = NSLock()
    private var timeout: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func installTimeout(_ task: Task<Void, Never>) {
        lock.lock()
        let pending = continuation != nil
        if pending { timeout = task }
        lock.unlock()
        if !pending { task.cancel() }
    }

    @discardableResult
    func resume(with result: Result<Value, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        let timer = timeout
        timeout = nil
        lock.unlock()
        timer?.cancel()
        pending?.resume(with: result)
        return pending != nil
    }
}

// MARK: - View model
