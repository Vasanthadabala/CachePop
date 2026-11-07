import Foundation
import ServiceManagement
import Testing
@testable import CachePop

@Suite("Fan control: SMC writes")
struct FanWritePlanTests {
    private let appleSilicon = ["Ftst": "ui8 ", "F0Md": "ui8 ", "F0Tg": "flt ", "F1Md": "ui8 ", "F1Tg": "flt "]

    @Test func appleSiliconUnlocksSetsManualThenTarget() throws {
        let writes = try #require(FanWritePlan.manual(fan: 0, rpm: 3_000, minimum: 1_200, maximum: 5_800, keyTypes: appleSilicon))
        #expect(writes.map(\.key) == ["Ftst", "F0Md", "F0Tg"])
        #expect(writes[0].bytes == [1])
        #expect(writes[1].bytes == [1])
        #expect(SMC.decode(type: "flt ", bytes: writes[2].bytes) == 3_000)
    }

    @Test func speedsAreClampedToWhatMacOSAllows() throws {
        let low = try #require(FanWritePlan.manual(fan: 0, rpm: 200, minimum: 1_200, maximum: 5_800, keyTypes: appleSilicon))
        #expect(SMC.decode(type: "flt ", bytes: low.last!.bytes) == 1_200)
        let high = try #require(FanWritePlan.manual(fan: 0, rpm: 99_000, minimum: 1_200, maximum: 5_800, keyTypes: appleSilicon))
        #expect(SMC.decode(type: "flt ", bytes: high.last!.bytes) == 5_800)
        #expect(FanWritePlan.clamp(-5, minimum: 1_000, maximum: 500) == 1_000)
    }

    @Test func olderIntelMacsUseTheForcedMask() throws {
        let intel = ["FS! ": "ui16", "F1Tg": "fpe2"]
        let writes = try #require(FanWritePlan.manual(fan: 1, rpm: 2_400, minimum: 1_000, maximum: 6_000, keyTypes: intel, forcedMask: 0b01))
        #expect(writes.map(\.key) == ["FS! ", "F1Tg"])
        #expect(writes[0].bytes == [0x00, 0b11])
        #expect(writes[1].bytes == [0x25, 0x80])

        let release = FanWritePlan.automatic(fan: 1, othersManual: true, keyTypes: intel, forcedMask: 0b11)
        #expect(release == [SMCWrite(key: "FS! ", bytes: [0x00, 0b01])])
    }

    @Test func unsupportedOrFanlessMacsGetNoPlan() {
        #expect(FanWritePlan.manual(fan: 0, rpm: 2_000, minimum: 1_000, maximum: 5_000, keyTypes: [:]) == nil)
        #expect(FanWritePlan.manual(fan: 0, rpm: 2_000, minimum: 1_000, maximum: 5_000, keyTypes: ["F0Tg": "flt "]) == nil)
        #expect(FanWritePlan.manual(fan: 0, rpm: 2_000, minimum: 0, maximum: 0, keyTypes: appleSilicon) == nil)
    }

    @Test func automaticKeepsTheUnlockWhileOtherFansAreManual() {
        let keepUnlocked = FanWritePlan.automatic(fan: 0, othersManual: true, keyTypes: appleSilicon)
        #expect(keepUnlocked == [SMCWrite(key: "F0Md", bytes: [0])])
        let lastOne = FanWritePlan.automatic(fan: 1, othersManual: false, keyTypes: appleSilicon)
        #expect(lastOne == [SMCWrite(key: "F1Md", bytes: [0]), SMCWrite(key: "Ftst", bytes: [0])])
    }

    @Test func numbersRoundTrip() {
        for value in [0.0, 1_200, 2_412.5, 6_000] {
            #expect(SMC.decode(type: "flt ", bytes: SMC.encode(value, type: "flt ")!) == value)
            #expect(SMC.decode(type: "fpe2", bytes: SMC.encode(value, type: "fpe2")!) == value)
        }
        #expect(SMC.encode(1, type: "ch8*") == nil)
    }
}

/// Records what the view model asks of the helper.
@MainActor
final class RecordingFanController: FanControlling {
    var status: FanHelperStatus = .ready
    var speeds: [Int: Double] = [:]
    var releasedAll = 0
    var failSpeed = false
    /// What the failure says, and the status the helper is left in (an update awaiting approval).
    var failSpeedMessage = "The fan didn't accept the new speed."
    var statusAfterFailure: FanHelperStatus?
    var installed = false
    var onHelperRestarted: () -> Void = {}

    func install() throws { installed = true; status = .needsApproval }
    func uninstall() async throws { status = .notInstalled }
    func openApprovalSettings() {}
    func setSpeed(fan: Int, rpm: Double) async throws {
        if failSpeed {
            if let statusAfterFailure { status = statusAfterFailure }
            throw FanControlError(message: failSpeedMessage)
        }
        speeds[fan] = rpm
    }
    func setAutomatic(fan: Int) async throws { speeds[fan] = nil }
    func setAllAutomatic() async throws {
        speeds = [:]
        releasedAll += 1
    }
}

@MainActor
@Suite("Fan control: app")
struct FanControlViewModelTests {
    private let fans = [FanSample(index: 0, rpm: 1_800, minimum: 1_200, maximum: 5_800),
                        FanSample(index: 1, rpm: 1_900, minimum: 1_300, maximum: 6_200)]

    @Test func customSpeedsAreClampedAndModeIsReported() async {
        let controller = RecordingFanController()
        let control = FanControlViewModel(controller: controller)
        var modes: [FanControlViewModel.Mode] = []
        control.onModeChanged = { modes.append($0) }

        control.targets = [0: 500, 1: 9_000]
        await control.apply(fans)
        #expect(controller.speeds == [0: 1_200, 1: 6_200])
        #expect(control.isCustom)

        await control.setAutomatic()
        #expect(controller.speeds.isEmpty)
        #expect(!control.isCustom)
        #expect(modes == [.custom, .automatic])
    }

    @Test func heatHandsFansBackToMacOS() async {
        let controller = RecordingFanController()
        let control = FanControlViewModel(controller: controller)
        await control.applyMaximum(fans)
        #expect(controller.speeds == [0: 5_800, 1: 6_200])

        await control.checkSafety(temperatures: TemperatureSample(chip: 70, chipMax: 80), thermalState: .nominal)
        #expect(control.isCustom)
        await control.checkSafety(temperatures: TemperatureSample(chip: 90, chipMax: 96), thermalState: .nominal)
        #expect(!control.isCustom)
        #expect(controller.releasedAll == 1)
        #expect(control.message?.contains("hot") == true)

        await control.apply(fans)
        await control.checkSafety(temperatures: TemperatureSample(chip: 60, chipMax: 62), thermalState: .serious)
        #expect(!control.isCustom)
    }

    @Test func aFailedSpeedChangeReleasesEveryFan() async {
        let controller = RecordingFanController()
        controller.failSpeed = true
        let control = FanControlViewModel(controller: controller)
        await control.apply(fans)
        #expect(!control.isCustom)
        #expect(controller.releasedAll == 1)
        #expect(control.message != nil)
    }

    @Test func installAsksForApproval() {
        let controller = RecordingFanController()
        controller.status = .notInstalled
        let control = FanControlViewModel(controller: controller)
        control.install()
        #expect(controller.installed)
        #expect(control.status == .needsApproval)
        #expect(control.message?.contains("Login Items") == true)
    }

    @Test func nothingIsSentBeforeTheHelperIsReady() async {
        let controller = RecordingFanController()
        controller.status = .notInstalled
        let control = FanControlViewModel(controller: controller)
        await control.apply(fans)
        #expect(controller.speeds.isEmpty)
        #expect(!control.isCustom)
    }

    @Test func aRestartedHelperShowsFansBackOnAutomatic() async {
        let controller = RecordingFanController()
        let control = FanControlViewModel(controller: controller)
        await control.applyMaximum(fans)
        #expect(control.isCustom)

        // As the live controller reports an interrupted connection.
        controller.onHelperRestarted()
        for _ in 0..<100 where control.isCustom { await Task.yield() }
        #expect(!control.isCustom)
        #expect(controller.releasedAll == 1)
        #expect(control.message?.contains("restarted") == true)
    }

    @Test func aRestartWhileAutomaticSendsNothing() async {
        let controller = RecordingFanController()
        let control = FanControlViewModel(controller: controller)
        await control.helperRestarted()
        #expect(controller.releasedAll == 0)
        #expect(control.message == nil)
    }

    @Test func anUpdateAwaitingApprovalKeepsItsMessage() async {
        let controller = RecordingFanController()
        controller.failSpeed = true
        controller.failSpeedMessage = "The fan helper was updated. Allow “CachePop” in System Settings › General › Login Items & Extensions, then try again."
        controller.statusAfterFailure = .needsApproval
        let control = FanControlViewModel(controller: controller)
        await control.apply(fans)
        #expect(!control.isCustom)
        // Nothing was set and nothing can be sent, so the approval message stays on screen.
        #expect(controller.releasedAll == 0)
        #expect(control.status == .needsApproval)
        #expect(control.message?.contains("Login Items") == true)
    }

    @Test func onlyAHelperOfAnotherVersionIsReplaced() {
        #expect(!LiveFanController.needsReplacing(runningVersion: FanHelperConstants.version))
        #expect(LiveFanController.needsReplacing(runningVersion: "1"))
        #expect(LiveFanController.needsReplacing(runningVersion: ""))
    }
}

@Suite("Fan control: bundle")
struct FanHelperBundleTests {
    /// The app ships the helper and its launchd plist where SMAppService looks for them.
    /// Only reads the registration status; nothing is registered.
    @MainActor
    @Test func helperAndPlistAreEmbedded() throws {
        let bundle = Bundle.main.bundleURL
        #expect(FileManager.default.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/CachePopFanHelper").path))
        let plistURL = bundle.appendingPathComponent("Contents/Library/LaunchDaemons/\(FanHelperConstants.plistName)")
        let plist = try #require(NSDictionary(contentsOf: plistURL) as? [String: Any])
        #expect(plist["Label"] as? String == FanHelperConstants.label)
        #expect(plist["BundleProgram"] as? String == "Contents/MacOS/CachePopFanHelper")
        #expect((plist["MachServices"] as? [String: Bool])?[FanHelperConstants.machServiceName] == true)
        // Relaunched after a crash only: still started on demand, and stays stopped once removed.
        #expect(plist["KeepAlive"] as? [String: Bool] == ["Crashed": true])
        #expect(plist["RunAtLoad"] == nil)
        #expect(LiveFanController.isEmbedded)
        // Reads the status only. Not installed on this Mac, but never "missing".
        let status = LiveFanController().status
        #expect(status == .notInstalled || status == .needsApproval || status == .ready)
    }
}
