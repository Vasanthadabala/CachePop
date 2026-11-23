import AppKit
import Foundation
import Testing
@testable import CachePop

@Suite("Network and sensor menus")
struct NetworkMenuTests {
    @Test func networkRunsWithoutProcessOrFullHardwareQueries() {
        for client in ["networkMenuBar", "networkMenu"] {
            let demand = MonitorDemand(clients: [client], visibleWindow: false, visibleMainWindow: false)
            #expect(demand.sampling && demand.network)
            #expect(!demand.details && !demand.processes && !demand.preloadsProcesses)
        }
        for client in ["sensorsMenuBar", "sensorsMenu"] {
            let demand = MonitorDemand(clients: [client], visibleWindow: false, visibleMainWindow: false)
            #expect(demand.sampling && demand.details)
            #expect(!demand.processes)
        }
        let disabled = MonitorDemand(clients: [], visibleWindow: false, visibleMainWindow: false)
        #expect(!disabled.sampling && !disabled.network)
    }

    @MainActor @Test func independentPreferencesSurviveRelaunchAndKeepTheAppRunning() throws {
        let suite = "CachePop.tests.network-settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, canChangeLoginItem: false)
        settings.showMenuBarItem = false
        #expect(!settings.showsAnyMenuBarItem)
        for kind in [UsageMenuKind.sensors, .network] {
            settings[keyPath: kind.setting] = true
            #expect(settings.showsAnyMenuBarItem)
            #expect(AppSettings(defaults: defaults, canChangeLoginItem: false)[keyPath: kind.setting])
            settings[keyPath: kind.setting] = false
            #expect(!settings.showsAnyMenuBarItem)
        }
        #expect(Array(UsageMenuKind.allCases.suffix(3)) == [.battery, .sensors, .network])
    }

    @MainActor @Test func chartsMirrorDirectionsWithOneSharedScaleAndKeepEmptyTimeBlank() {
        let size = CGSize(width: 119, height: 80)
        let upload = TrafficChartGeometry.points([0, 50, 100], upper: true, maximum: 100, capacity: 120, in: size)
        let download = TrafficChartGeometry.points([0, 25, 50], upper: false, maximum: 100, capacity: 120, in: size)
        #expect(upload.map(\.x) == [117, 118, 119])
        #expect(upload.map(\.y) == [40, 21, 2])
        #expect(download.map(\.y) == [40, 49.5, 59])
        #expect(TrafficChartGeometry.points([], upper: true, maximum: 1, capacity: 120, in: size).isEmpty)
        let invalid = TrafficChartGeometry.points([.nan, -.infinity, -2, 500], upper: true, maximum: 100, capacity: 3, in: size)
        #expect(invalid.count == 3)
        #expect(invalid.allSatisfy { $0.y.isFinite && (2...40).contains($0.y) && $0.x >= 0 })
    }

    @MainActor @Test func networkOnlySnapshotsUpdateBoundedTrafficHistory() {
        let model = SystemMonitorViewModel(sampler: NetworkFixtureSampler())
        var snapshot = SystemSnapshot(hasDetailedReadings: false)
        snapshot.network = Throughput(inPerSecond: 8_800_000, outPerSecond: 275_000)
        snapshot.networkReading = NetworkReading(counters: ByteCounters(read: 1_000, written: 500), interface: "en0", localAddress: "192.0.2.10")
        snapshot.hasNetworkReadings = true
        for _ in 0..<150 { model.apply(snapshot) }
        #expect(model.networkInHistory.count == 120 && model.networkOutHistory.count == 120)
        #expect(model.networkInHistory.last == 8_800_000)
        #expect(model.diskReadHistory.isEmpty && model.gpuHistories.isEmpty)
        snapshot.hasNetworkReadings = false
        snapshot.network = Throughput()
        model.apply(snapshot)
        #expect(model.networkInHistory.last == 8_800_000, "Unavailable readings must not fabricate zero traffic.")
        let reset = Throughput.between(ByteCounters(read: 1_000, written: 800), ByteCounters(read: 50, written: 10), seconds: 1)
        #expect(reset == Throughput())
    }

    @MainActor @Test func networkArrowsAreColoredValuesStayWhiteAndWidthIsStable() throws {
        let small = HardwareMenuBarLabel.networkImage(upload: "↑ 0 B/s", download: "↓ 1 KB/s")
        let large = HardwareMenuBarLabel.networkImage(upload: "↑ 999.9 MB/s", download: "↓ 999.9 MB/s")
        #expect(small.size == large.size)
        for (image, hasColoredArrows) in [(small, true), (large, true), (HardwareMenuBarLabel.sensorsImage(), false)] {
            #expect(!image.isTemplate)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            var visible = 0
            var redArrow = 0
            var blueArrow = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if color.alphaComponent > 0.1 {
                        visible += 1
                        if min(color.redComponent, color.greenComponent, color.blueComponent) <= 0.95 {
                            #expect(hasColoredArrows)
                            #expect(CGFloat(x) / CGFloat(bitmap.pixelsWide) < 0.2, "Only the arrows should be colored.")
                            if color.redComponent > color.blueComponent * 1.5 {
                                redArrow += 1
                                #expect(y < bitmap.pixelsHigh / 2, "Upload belongs on the top row.")
                            }
                            if color.blueComponent > color.redComponent * 1.5 {
                                blueArrow += 1
                                #expect(y >= bitmap.pixelsHigh / 2, "Download belongs on the bottom row.")
                            }
                        }
                    }
                }
            }
            #expect(visible > 20)
            if hasColoredArrows {
                #expect(redArrow > 2 && blueArrow > 2)
            } else {
                #expect(redArrow == 0 && blueArrow == 0)
            }
        }
    }
}

private actor NetworkFixtureSampler: SystemSampling {
    func sample(includeProcesses: Bool, includeDetails: Bool) async -> SystemSnapshot { SystemSnapshot() }
}
