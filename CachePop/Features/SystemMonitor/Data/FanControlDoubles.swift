import Foundation

/// Used by the test host: never installs or talks to the real helper.
@MainActor
final class InertFanController: FanControlling {
    var status: FanHelperStatus { .unavailable("Fan control is off while testing.") }
    var onHelperRestarted: () -> Void = {}
    func install() throws {}
    func uninstall() async throws {}
    func openApprovalSettings() {}
    func setSpeed(fan: Int, rpm: Double) async throws {}
    func setAllAutomatic() async throws {}
}

#if DEBUG
/// Demo mode: two pretend fans that follow the speeds CachePop sets, so the controls can be
/// shown and checked on a Mac without fans.
nonisolated final class DemoFans: @unchecked Sendable {
    private let lock = NSLock()
    private var fans = [
        FanSample(index: 0, rpm: 1_840, minimum: 1_200, maximum: 5_800),
        FanSample(index: 1, rpm: 1_910, minimum: 1_200, maximum: 6_200)
    ]
    private var manual: [Int: Double] = [:]

    func read() -> [FanSample] {
        lock.withLock {
            fans.map { fan in
                var fan = fan
                fan.rpm = manual[fan.index] ?? fan.rpm + Double.random(in: -40...40)
                return fan
            }
        }
    }

    func set(_ fan: Int, rpm: Double?) {
        lock.withLock { manual[fan] = rpm }
    }

    func releaseAll() {
        lock.withLock { manual = [:] }
    }
}

@MainActor
final class DemoFanController: FanControlling {
    private let fans: DemoFans
    private(set) var status: FanHelperStatus = .notInstalled
    var onHelperRestarted: () -> Void = {}

    init(fans: DemoFans) {
        self.fans = fans
    }

    func install() throws { status = .ready }
    func uninstall() async throws {
        fans.releaseAll()
        status = .notInstalled
    }
    func openApprovalSettings() {}
    func setSpeed(fan: Int, rpm: Double) async throws {
        guard let sample = fans.read().first(where: { $0.index == fan }) else {
            throw FanControlError(message: "This Mac has no fan \(fan + 1).")
        }
        fans.set(fan, rpm: FanWritePlan.clamp(rpm, minimum: sample.minimum, maximum: sample.maximum))
    }
    func setAllAutomatic() async throws { fans.releaseAll() }
}
#endif
