#if DEBUG
import AppKit
import Darwin
import Foundation

/// Opt-in measurements for the disposable memory UI test. Never included in Release.
@MainActor
enum MemoryDiagnostics {
    private struct Reading: Encodable {
        let seconds: Int
        let physicalBytes: UInt64
        let residentBytes: UInt64
        let peakPhysicalBytes: UInt64
        let hidden: Bool
        let visibleMainWindow: Bool
        let section: String
        let photoCount: Int
    }

    static func start(_ model: AppModel) {
        guard DemoMode.isMemoryUITest,
              let path = ProcessInfo.processInfo.environment["CACHEPOP_MEMORY_REPORT"],
              path.hasPrefix("/tmp/CachePop-memory-") else { return }
        Task { [weak model] in
            var readings: [Reading] = []
            for second in 0..<180 {
                guard !Task.isCancelled, model != nil else { return }
                if let model, let reading = read(model, second: second) { readings.append(reading) }
                if let data = try? JSONEncoder().encode(readings) {
                    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func read(_ model: AppModel, second: Int) -> Reading? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, UnsafeMutableRawPointer($0).assumingMemoryBound(to: rusage_info_t?.self))
        }
        guard result == 0 else { return nil }
        return Reading(seconds: second, physicalBytes: usage.ri_phys_footprint,
                       residentBytes: usage.ri_resident_size,
                       peakPhysicalBytes: usage.ri_lifetime_max_phys_footprint,
                       hidden: NSApp.isHidden,
                       visibleMainWindow: NSApp.windows.contains { $0.canBecomeMain && $0.isVisible },
                       section: model.section?.rawValue ?? "cleanUp",
                       photoCount: model.photos.result.analyzedCount)
    }
}
#endif
