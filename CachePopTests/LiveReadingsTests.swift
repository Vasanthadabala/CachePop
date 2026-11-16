import Foundation
import Testing
@testable import CachePop

@Suite("Live readings", .serialized)
struct LiveReadingsTests {
    actor DelayedSampler: SystemSampling {
        private(set) var starts: [ContinuousClock.Instant] = []

        func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot {
            starts.append(.now)
            let reading = starts.count
            try? await Task.sleep(for: .milliseconds(150))
            return SystemSnapshot(cpu: CPUSample(total: Double(reading) / 100),
                                  memory: MemorySample(total: 1_000, app: Int64(reading)),
                                  temperatures: TemperatureSample(chip: Double(40 + reading)),
                                  hasDetailedReadings: includeDetails)
        }
    }

    @MainActor
    @Test func menuBarReadingsStayLiveAndSamplingTimeDoesNotAddToTheInterval() async throws {
        let sampler = DelayedSampler()
        let monitor = SystemMonitorViewModel(sampler: sampler)
        monitor.begin(SystemMonitorViewModel.menuBarClient)
        defer { monitor.end(SystemMonitorViewModel.menuBarClient) }
        for _ in 0..<450 {
            if await sampler.starts.count >= 4 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let starts = await sampler.starts
        try #require(starts.count >= 4, "Menu bar readings must keep refreshing without an open window.")
        #expect(starts[0].duration(to: starts[3]) >= .milliseconds(2_750))
        #expect(starts[0].duration(to: starts[3]) < .milliseconds(3_350),
                "Sampling work must count toward the refresh interval.")
        let reading = try #require(monitor.snapshot)
        #expect(reading.cpu.total >= 0.02)
        #expect(reading.memory.app >= 2)
        #expect((reading.temperatures.chip ?? 0) >= 42)
    }

    @Test func nativePopoverClientsRequestProcessesWithoutAppKitWindowVisibility() {
        for client in ["cpuMenu", "memoryMenu"] {
            let demand = MonitorDemand(clients: [client], visibleWindow: false, visibleMainWindow: false)
            #expect(demand.sampling)
            #expect(demand.processes)
            #expect(!demand.details)
        }
        let hiddenSection = MonitorDemand(clients: ["section"], visibleWindow: false, visibleMainWindow: false)
        #expect(!hiddenSection.sampling && !hiddenSection.processes)
        let drive = MonitorDemand(clients: ["driveMenu"], visibleWindow: false, visibleMainWindow: false)
        #expect(drive.sampling && drive.details && !drive.processes)
    }

    @MainActor
    @Test func onlyCPUAndMemoryItemsPreloadProcessesWithoutVisibleWindows() {
        let preload = MonitorDemand(clients: [SystemMonitorViewModel.processMenuBarClient], visibleWindow: false, visibleMainWindow: false)
        #expect(preload.sampling && preload.processes && preload.preloadsProcesses)
        #expect(!preload.processView && !preload.details)
        for client in [SystemMonitorViewModel.menuBarClient, "temperatureMenu", "fanMenu", "driveMenu"] {
            let demand = MonitorDemand(clients: [client], visibleWindow: false, visibleMainWindow: false)
            #expect(!demand.processes && !demand.preloadsProcesses)
        }
        let disabled = MonitorDemand(clients: [], visibleWindow: false, visibleMainWindow: false)
        #expect(!disabled.sampling && !disabled.processes)
    }

    actor PreloadedSampler: SystemSampling {
        private(set) var processRequests: [Bool] = []
        private(set) var stops = 0

        func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot {
            processRequests.append(includeProcesses)
            let processes = (1...30).map {
                ProcessUsage(pid: Int32($0), name: "Fixture \($0)", cpuPercent: Double($0), memoryBytes: Int64(31 - $0) * 1024)
            }
            return SystemSnapshot(processes: includeProcesses ? processes : nil,
                                  hasDetailedReadings: includeDetails,
                                  processStatus: includeProcesses ? .ready : .idle)
        }

        func cancelPendingReadings() async { stops += 1 }
    }

    @MainActor
    @Test func processesAreReadyBeforeTheFirstPopupAndSharedUntilTheLastItemIsDisabled() async throws {
        let sampler = PreloadedSampler()
        let monitor = SystemMonitorViewModel(sampler: sampler)
        let client = SystemMonitorViewModel.processMenuBarClient
        // CPU and Memory share one sampling loop, each with its own lifetime.
        monitor.begin(client)
        monitor.begin(client)
        defer { monitor.end("cpuMenu"); monitor.end(client); monitor.end(client) }
        for _ in 0..<100 where monitor.menuProcesses().isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.processStatus == .ready)
        #expect(monitor.menuProcesses().count == 10)
        #expect(monitor.menuProcesses().contains { $0.pid == 30 })
        #expect(monitor.menuProcesses().contains { $0.pid == 1 })
        #expect(monitor.processes.isEmpty)
        #expect(monitor.snapshot?.processes == nil)
        let requestsBeforeOpening = await sampler.processRequests.count
        monitor.begin("cpuMenu")
        #expect(!monitor.menuProcesses().isEmpty)
        monitor.end("cpuMenu")
        #expect(monitor.processStatus == .ready)
        #expect(await sampler.stops == 0, "Opening/closing a popup must not restart background collection.")
        #expect(await sampler.processRequests.count == requestsBeforeOpening)

        monitor.end(client)
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(await sampler.processRequests.count >= 2, "Memory still needs readings after CPU is disabled.")
        #expect(await sampler.processRequests.allSatisfy { $0 })
        monitor.end(client)
        for _ in 0..<100 where await sampler.stops == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await sampler.stops == 1)
        let stoppedAt = await sampler.processRequests.count
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(await sampler.processRequests.count == stoppedAt, "Disabling the last item must stop background collection.")
    }

    @MainActor
    @Test func reopenedPopupsUseABoundedRecentCacheAndMemoryTrimmingDiscardsIt() {
        let model = SystemMonitorViewModel()
        let processes = (1...30).map {
            ProcessUsage(pid: Int32($0), name: "Fixture \($0)", cpuPercent: Double($0), memoryBytes: Int64(31 - $0) * 1024)
        }
        model.apply(SystemSnapshot(processes: processes))
        model.releaseUnusedProcessDetails()
        #expect(model.processes.isEmpty)
        #expect(model.menuProcesses().count <= 10)
        #expect(model.menuProcesses().contains { $0.pid == 30 })
        #expect(model.menuProcesses().contains { $0.pid == 1 })
        #expect(model.menuProcesses(at: .now.advanced(by: .seconds(11))).isEmpty)
        model.releaseUnusedProcessDetails(discardMenuCache: true)
        #expect(model.menuProcesses().isEmpty)
    }

    @Test func failedProcessCommandsReportUnavailableInsteadOfLoadingForever() async throws {
        let runner = FakeCommandRunner { _ in CommandOutput(status: 1, stdout: "", stderr: "Failed fixture") }
        let sampler = SystemSampler(runner: runner)
        var reading = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 where reading.processStatus != .unavailable {
            try await Task.sleep(for: .milliseconds(5))
            reading = await sampler.sample(includeProcesses: true, includeDetails: false)
        }
        #expect(reading.processStatus == .unavailable)
        #expect(reading.processes == nil)
        #expect(!reading.processStatus.message.contains("Reading"))
        await sampler.cancelPendingReadings()
    }

    @Test func emptySuccessfulProcessCommandsFinishLoading() async throws {
        let runner = FakeCommandRunner { _ in CommandOutput(status: 0, stdout: "", stderr: "") }
        let sampler = SystemSampler(runner: runner)
        var reading = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 where reading.processes == nil {
            try await Task.sleep(for: .milliseconds(5))
            reading = await sampler.sample(includeProcesses: true, includeDetails: false)
        }
        #expect(reading.processStatus == .ready)
        #expect(reading.processes == [])
        await sampler.cancelPendingReadings()
    }

    actor HeldProcessRunner: CommandRunning {
        private(set) var calls = 0
        private var pending: [Int: CheckedContinuation<CommandOutput, Never>] = [:]
        func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
            calls += 1
            let call = calls
            return await withCheckedContinuation { pending[call] = $0 }
        }
        func finish(_ call: Int, pid: Int) {
            pending.removeValue(forKey: call)?.resume(returning: CommandOutput(status: 0, stdout: "\(pid) 5.0 1024 /usr/bin/fixture", stderr: ""))
        }
        func finishAll() {
            for continuation in pending.values { continuation.resume(returning: CommandOutput(status: 0, stdout: "", stderr: "")) }
            pending = [:]
        }
    }

    @Test func aCancelledPopupQueryCannotOverwriteAReopenedPopupsQuery() async throws {
        let runner = HeldProcessRunner()
        defer { Task { await runner.finishAll() } }
        let sampler = SystemSampler(runner: runner)
        _ = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 where await runner.calls < 1 { try await Task.sleep(for: .milliseconds(5)) }
        _ = await sampler.sample(includeProcesses: false, includeDetails: false)
        _ = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 where await runner.calls < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await runner.calls == 2)
        await runner.finish(1, pid: 111)
        await runner.finish(2, pid: 222)
        var reading = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 where reading.processes == nil {
            try await Task.sleep(for: .milliseconds(5))
            reading = await sampler.sample(includeProcesses: true, includeDetails: false)
        }
        #expect(reading.processes?.map(\.pid) == [222])
        #expect(reading.processStatus == .ready)
        await sampler.cancelPendingReadings()
    }

    actor SlowHelpers: CommandRunning {
        private(set) var processStarts = 0
        private(set) var healthStarts = 0
        private(set) var cancellations = 0

        func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
            processStarts += 1
            do { try await Task.sleep(for: .seconds(3)) }
            catch { cancellations += 1; throw error }
            return CommandOutput(status: 0, stdout: "123 5.0 1024 /usr/bin/fixture", stderr: "")
        }

        func health() async -> Double? {
            healthStarts += 1
            do { try await Task.sleep(for: .seconds(3)) }
            catch { cancellations += 1; return nil }
            return 0.95
        }
    }

    @Test func slowProcessAndBatteryQueriesCannotHoldUpLiveReadingsAndAreCancelledOnStop() async throws {
        let helpers = SlowHelpers()
        let sampler = SystemSampler(runner: helpers, batteryHealthSource: { await helpers.health() })
        _ = await sampler.sample(includeProcesses: false, includeDetails: false)
        let start = ContinuousClock.now
        let first = await sampler.sample(includeProcesses: true, includeDetails: true)
        #expect(start.duration(to: .now) < .milliseconds(500))
        #expect(first.memory.total > 0)
        for _ in 0..<100 {
            if await helpers.processStarts == 1, await helpers.healthStarts == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let next = ContinuousClock.now
        let second = await sampler.sample(includeProcesses: true, includeDetails: true)
        #expect(next.duration(to: .now) < .milliseconds(500))
        #expect(second.memory.total > 0)
        #expect((0...1).contains(second.cpu.total))
        #expect(await helpers.processStarts == 1)
        #expect(await helpers.healthStarts == 1)
        await sampler.cancelPendingReadings()
        for _ in 0..<100 {
            if await helpers.cancellations == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let cancellations = await helpers.cancellations
        #expect(cancellations == 2)
    }

    actor OrderedProcesses: CommandRunning {
        private(set) var calls = 0
        private var firstCommand: CheckedContinuation<Void, Never>?

        func run(_ command: ToolCommand, timeout: TimeInterval) async throws -> CommandOutput {
            calls += 1
            let call = calls
            if call == 1 {
                // Deliberately finish after cancellation to exercise a late command callback.
                await withCheckedContinuation { firstCommand = $0 }
            }
            return CommandOutput(status: 0, stdout: "\(call) 5.0 1024 /usr/bin/fixture", stderr: "")
        }

        func finishFirstCommand() {
            firstCommand?.resume()
            firstCommand = nil
        }
    }

    @Test func aCancelledProcessQueryCannotReplaceNewerResults() async throws {
        let runner = OrderedProcesses()
        let sampler = SystemSampler(runner: runner)
        _ = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 {
            if await runner.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        _ = await sampler.sample(includeProcesses: false, includeDetails: false)
        var current = await sampler.sample(includeProcesses: true, includeDetails: false)
        for _ in 0..<100 where current.processes == nil {
            try await Task.sleep(for: .milliseconds(5))
            current = await sampler.sample(includeProcesses: true, includeDetails: false)
        }
        await runner.finishFirstCommand()
        #expect(current.processes?.map(\.pid) == [2])
        try await Task.sleep(for: .milliseconds(50))
        let next = await sampler.sample(includeProcesses: true, includeDetails: false)
        #expect(next.processes == nil, "Cancelled command output must never be published.")
        await sampler.cancelPendingReadings()
    }
}
