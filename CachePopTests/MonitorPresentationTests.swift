import AppKit
import SwiftUI
import Testing
@testable import CachePop

@Suite("Monitor presentation")
@MainActor
struct MonitorPresentationTests {
    @Test func sensorsPopupDoublesItsHeightAndKeepsItsFooterOnScreen() {
        let chrome: CGFloat = 140
        let roomy = SensorsPopupLayout.readingsHeight(rowCount: 30, availableHeight: 1_200)
        #expect(roomy + chrome == (350 + chrome) * 2)
        for available: CGFloat in [500, 720, 900] {
            let height = SensorsPopupLayout.readingsHeight(rowCount: 30, availableHeight: available)
            #expect(height + chrome <= available)
            #expect(height >= 350)
        }
    }

    @Test func quitAvailabilityDoesNotMoveProcessText() throws {
        for value in ["10.6%", "524 MB"] {
            let without = try render(ActivityProcessRow(pid: 1453, name: "Worker", value: value, showsQuitColumn: true)
                .foregroundStyle(.white).frame(width: 640, height: 32).background(.black), scheme: .dark)
            let with = try render(ActivityProcessRow(pid: 1453, name: "Worker", value: value,
                                                     showsQuitColumn: true, onQuit: {})
                .foregroundStyle(.white).frame(width: 640, height: 32).background(.black), scheme: .dark)
            var lastTextX = -1
            var firstDifferenceX = without.pixelsWide
            for y in 0..<without.pixelsHigh {
                for x in 0..<without.pixelsWide {
                    let a = try #require(without.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let b = try #require(with.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if min(a.redComponent, a.greenComponent, a.blueComponent) > 0.9 { lastTextX = max(lastTextX, x) }
                    let difference = max(abs(a.redComponent - b.redComponent),
                                         abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))
                    if difference > 0.02 { firstDifferenceX = min(firstDifferenceX, x) }
                }
            }
            #expect(lastTextX >= 0)
            #expect(firstDifferenceX < without.pixelsWide)
            #expect(firstDifferenceX > lastTextX, "Only the final Quit column may change when an action becomes available.")
        }
    }

    @Test func renderProcessAndChargeProof() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17))!
        let now = start.addingTimeInterval(15 * 3_600)
        var history = RollingBatteryHistory(now: now, calendar: calendar)
        for minute in 0...900 where !(540..<600).contains(minute) {
            history.record(percent: max(45, 96 - minute / 18), at: start.addingTimeInterval(Double(minute * 60)), calendar: calendar)
        }
        let processes = [
            ProcessUsage(pid: 1453, name: "Browser", cpuPercent: 10.6, memoryBytes: 549_453_824),
            ProcessUsage(pid: 90094, name: "Worker", cpuPercent: 1.6, memoryBytes: 455_920_845),
            ProcessUsage(pid: 25625, name: "Editor", cpuPercent: 1.0, memoryBytes: 366_162_739),
            ProcessUsage(pid: 1593, name: "Background service", cpuPercent: 0.8, memoryBytes: 364_589_875)
        ]
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CachePop-monitor-proof", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            let view = VStack(spacing: 14) {
                ForEach(["CPU", "Memory"], id: \.self) { metric in
                    MonitorGroup(title: "\(metric) process alignment") {
                        ActivityColumnHeader(value: metric, showsQuitColumn: true)
                        ForEach(Array(processes.enumerated()), id: \.element.pid) { index, process in
                            ActivityProcessRow(pid: process.pid, name: process.name,
                                               value: metric == "CPU" ? String(format: "%.1f%%", process.cpuPercent) : ByteSize.memory(process.memoryBytes),
                                               showsQuitColumn: true, onQuit: index.isMultiple(of: 2) ? {} : nil)
                        }
                    }
                }
                BatteryChargeChart(history: history, color: Metric.battery.solid)
                DriveHistoryChart(title: "Read / Write history", reads: (0..<120).map { abs(sin(Double($0) * 0.23)) * 8_000_000 },
                                  writes: (0..<120).map { abs(sin(Double($0) * 0.41)) * 2_000_000 })
            }.padding(18).frame(width: 720).foregroundStyle(AppTheme.Colors.textPrimary).background(AppTheme.Colors.canvas)
            let bitmap = try render(view, scheme: scheme)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let file = folder.appendingPathComponent(scheme == .dark ? "monitor-dark.png" : "monitor-light.png")
            try data.write(to: file)
            print("Monitor render proof: \(file.path)")
        }
    }

    @Test func historyAreasAreFilledAndTrafficDirectionsAreSeparate() throws {
        let chart = Sparkline(values: Array(repeating: 0.75, count: 120), maximum: 1, color: .blue)
            .frame(width: 120, height: 80).background(.black)
        let line = try render(chart, scheme: .dark)
        let fill = try #require(line.colorAt(x: 120, y: 120)?.usingColorSpace(.deviceRGB))
        #expect(fill.blueComponent > fill.redComponent + 0.2, "The area beneath the line must have a visible color fill.")
        let traffic = try render(TrafficHistoryChart(incoming: Array(repeating: 100, count: 120),
                                                    outgoing: Array(repeating: 50, count: 120))
            .frame(width: 120, height: 80).background(.black), scheme: .dark)
        let upper = try #require(traffic.colorAt(x: 120, y: 60)?.usingColorSpace(.deviceRGB))
        let lower = try #require(traffic.colorAt(x: 120, y: 120)?.usingColorSpace(.deviceRGB))
        #expect(upper.redComponent > upper.blueComponent + 0.2)
        #expect(lower.blueComponent > lower.redComponent + 0.2)
    }

    @Test func renderNetworkAndSensorPopupProof() throws {
        var snapshot = SystemSnapshot()
        snapshot.temperatures = TemperatureSample(chip: 52, chipMax: 58, ssd: 37, battery: 33, memory: 40,
                                                  sensors: [.init(id: "cpu0", name: "CPU efficiency core 1", group: .cpu, celsius: 52),
                                                            .init(id: "gpu0", name: "GPU die", group: .gpu, celsius: 47)], gpu: 47)
        snapshot.electricalSensors = [.init(id: "PSTR", name: "System total", kind: .power, value: 10.4),
                                      .init(id: "V0", name: "DC input", kind: .voltage, value: 20.3),
                                      .init(id: "I0", name: "DC input", kind: .current, value: 0.4)]
        let incoming = (0..<120).map { 100_000 + abs(sin(Double($0) * 0.23)) * 8_000_000 }
        let outgoing = (0..<120).map { 10_000 + abs(sin(Double($0) * 0.41)) * 2_000_000 }
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        var usage = NetworkUsageHistory()
        func sample(_ read: UInt64, _ written: UInt64) -> NetworkReading {
            NetworkReading(counters: ByteCounters(read: read, written: written), interface: "en0", localAddress: nil)
        }
        usage.record(sample(0, 0), at: yesterday)
        usage.record(sample(9_000_000_000, 1_000_000_000), at: yesterday.addingTimeInterval(1))
        usage.record(sample(10_000_000_000, 2_000_000_000), at: now.addingTimeInterval(-1))
        usage.record(sample(10_500_000_000, 2_025_000_000), at: now)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CachePop-monitor-proof", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            let view = HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Network").font(.system(size: 14, weight: .bold))
                    NetworkMenuReadings(reading: NetworkReading(counters: ByteCounters(read: 18_300_000_000, written: 2_100_000_000),
                                                                interface: "en0", localAddress: "192.0.2.10"),
                                        throughput: Throughput(inPerSecond: 8_800_000, outPerSecond: 275_000),
                                        incoming: incoming, outgoing: outgoing, usage: usage)
                    Divider()
                    MenuRow(title: "Network Settings", symbol: "network", action: {})
                    MenuRow(title: "Menu Bar Settings", symbol: "menubar.rectangle", action: {})
                    MenuRow(title: "Quit CachePop", symbol: "power", action: {})
                }.padding(14).frame(width: 300).background(AppTheme.Colors.card, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sensors").font(.system(size: 14, weight: .bold))
                    SensorsMenuGroups(snapshot: snapshot).frame(height: 700, alignment: .top).clipped()
                    Divider()
                    MenuRow(title: "System Monitor", symbol: "chart.xyaxis.line", action: {})
                    MenuRow(title: "Menu Bar Settings", symbol: "menubar.rectangle", action: {})
                    MenuRow(title: "Quit CachePop", symbol: "power", action: {})
                }.padding(14).frame(width: 300).background(AppTheme.Colors.card, in: RoundedRectangle(cornerRadius: 14))
            }.padding(20).foregroundStyle(AppTheme.Colors.textPrimary).background(AppTheme.Colors.canvas)
            let bitmap = try render(view, scheme: scheme)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let file = folder.appendingPathComponent(scheme == .dark ? "popups-dark.png" : "popups-light.png")
            try data.write(to: file)
            print("Popup render proof: \(file.path)")
        }
    }

    private func render<Content: View>(_ content: Content, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, scheme))
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        return NSBitmapImageRep(cgImage: try #require(image))
    }
}
