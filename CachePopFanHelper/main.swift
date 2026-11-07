import Foundation

// CachePopFanHelper: a small launchd daemon that runs as root and does exactly one thing —
// set fan speeds through the SMC when CachePop asks.
//
// Safety:
// - Only CachePop signed by the same team can connect (code-signing requirement on the listener).
// - Speeds are clamped to the range macOS reports for each fan; never below its minimum.
// - Every fan goes back to automatic when CachePop disconnects (quit or crash), when the helper
//   stops, and whenever macOS reports the Mac as hot.
//
// `CachePopFanHelper --dry-run` prints what it would write, without writing, for checking.

final class FanService: NSObject, FanHelperProtocol {
    private let smc = SMC()
    private let queue = DispatchQueue(label: "com.piggylabs.CachePop.FanHelper.smc")
    private var manualFans = Set<Int>()
    private var watchdog: DispatchSourceTimer?

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(FanHelperConstants.version)
    }

    func setFanSpeed(_ fan: Int, rpm: Double, reply: @escaping (String?) -> Void) {
        queue.async {
            reply(self.applyManual(fan: fan, rpm: rpm))
        }
    }

    func setAutomatic(_ fan: Int, reply: @escaping (String?) -> Void) {
        queue.async {
            reply(self.applyAutomatic(fan: fan))
        }
    }

    func setAllAutomatic(reply: @escaping (String?) -> Void) {
        queue.async {
            reply(self.releaseAll())
        }
    }

    /// Called when the app goes away and when the helper stops.
    func releaseAllNow() {
        queue.sync { _ = releaseAll() }
    }

    // MARK: Work (on `queue`)

    private func applyManual(fan: Int, rpm: Double) -> String? {
        guard smc.isAvailable else { return "The fan controller couldn't be opened." }
        guard fan >= 0, fan < smc.fanCount else { return "This Mac has no fan \(fan + 1)." }
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            return "The Mac is hot, so its fans stay under macOS's control."
        }
        let minimum = smc.number("F\(fan)Mn") ?? 0
        let maximum = smc.number("F\(fan)Mx") ?? 0
        let mask = smc.number("FS! ").map { UInt16($0) }
        guard let writes = FanWritePlan.manual(fan: fan, rpm: rpm, minimum: minimum, maximum: maximum,
                                               keyTypes: smc.fanKeyTypes(fan: fan), forcedMask: mask) else {
            return "This Mac doesn't allow its fan speed to be set."
        }

        // Tracked before the first write, so a fan left half-set is still released and watched.
        manualFans.insert(fan)
        startWatchdog()
        for write in writes {
            // Apple silicon can take a moment to accept manual mode after unlocking.
            var attempts = 0
            while !smc.write(write.key, bytes: write.bytes) {
                attempts += 1
                if attempts >= 10 {
                    _ = applyAutomatic(fan: fan)
                    return "The fan didn't accept the new speed (\(write.key))."
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        return nil
    }

    /// `othersManual` overrides whether other fans still need the SMC unlocked.
    private func applyAutomatic(fan: Int, othersManual: Bool? = nil) -> String? {
        guard smc.isAvailable else { return "The fan controller couldn't be opened." }
        let others = othersManual ?? !manualFans.subtracting([fan]).isEmpty
        let mask = smc.number("FS! ").map { UInt16($0) }
        let writes = FanWritePlan.automatic(fan: fan, othersManual: others,
                                            keyTypes: smc.fanKeyTypes(fan: fan), forcedMask: mask)
        let failed = writes.filter { !smc.write($0.key, bytes: $0.bytes) }
        // A fan that couldn't be handed back stays tracked, so the watchdog keeps running and
        // tries again when the Mac gets hot.
        guard failed.isEmpty else { return "Couldn't hand fan \(fan + 1) back to macOS." }
        manualFans.remove(fan)
        if manualFans.isEmpty { stopWatchdog() }
        return nil
    }

    private func releaseAll() -> String? {
        let fans = Set(0..<max(smc.fanCount, 0)).union(manualFans).sorted()
        // Every fan is going back, so the last one always locks the SMC again, even when a fan
        // before it couldn't be handed back and is still tracked.
        let failures = fans.enumerated().compactMap { index, fan in
            applyAutomatic(fan: fan, othersManual: index < fans.count - 1)
        }
        return failures.first
    }

    /// Hands every fan back to macOS as soon as it reports the Mac as hot.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, !self.manualFans.isEmpty else { return }
            if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                _ = self.releaseAll()
            }
        }
        timer.resume()
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    // MARK: Dry run

    func dryRun() {
        guard smc.isAvailable else { return print("SMC: not available") }
        let fans = smc.fans()
        print("SMC: open · fans: \(fans.count) · running as \(getuid() == 0 ? "root" : "user \(getuid())")")
        for fan in fans {
            let keyTypes = smc.fanKeyTypes(fan: fan.index)
            let middle = (fan.minimum + fan.maximum) / 2
            let plan = FanWritePlan.manual(fan: fan.index, rpm: middle, minimum: fan.minimum, maximum: fan.maximum, keyTypes: keyTypes)
            print("Fan \(fan.index + 1): \(Int(fan.rpm)) rpm (\(Int(fan.minimum))–\(Int(fan.maximum))) keys \(keyTypes)")
            print("  would write: \(plan.map { $0.map { "\($0.key)=\($0.bytes)" }.joined(separator: ", ") } ?? "unsupported")")
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    let service = FanService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = service
        let closed: () -> Void = { [weak self] in self?.connectionClosed() }
        connection.invalidationHandler = closed
        connection.interruptionHandler = closed
        connection.resume()
        return true
    }

    /// A copy of CachePop quit or crashed: never leave fans on a fixed speed without it. Every
    /// fan is released, even while another copy stays connected (one run from Xcode, say): that
    /// copy doesn't know about, or watch the heat for, the speeds this one set.
    private func connectionClosed() {
        service.releaseAllNow()
    }
}

if CommandLine.arguments.contains("--dry-run") {
    FanService().dryRun()
    exit(0)
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: FanHelperConstants.machServiceName)
listener.setConnectionCodeSigningRequirement(FanHelperConstants.clientRequirement)
listener.delegate = delegate

// launchd sends SIGTERM when the helper is unloaded or the Mac shuts down.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    delegate.service.releaseAllNow()
    exit(0)
}
termination.resume()

// Start from a known state in case an earlier run ended without cleaning up.
delegate.service.releaseAllNow()
listener.resume()
RunLoop.main.run()
