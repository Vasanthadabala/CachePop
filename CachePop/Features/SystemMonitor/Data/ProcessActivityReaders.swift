import Darwin
import Foundation
import IOKit

nonisolated final class GPUProcessReader {
    struct Client: Equatable {
        let pid: Int32
        let name: String
        let nanoseconds: UInt64
        let queues: Int
    }
    private var previous: [UInt64: Client] = [:]
    private var date: ContinuousClock.Instant?

    func read(at now: ContinuousClock.Instant = .now) -> [GPUProcessUsage] {
        sample(Self.clients(), at: now)
    }

    func sample(_ current: [UInt64: Client], at now: ContinuousClock.Instant) -> [GPUProcessUsage] {
        defer { previous = current; date = now }
        guard let date else { return [] }
        let elapsed = date.duration(to: now).secondsValue
        guard elapsed > 0, elapsed <= 10 else { return [] }
        var totals: [Int32: (String, Double)] = [:]
        for (id, client) in current {
            guard let old = previous[id], old.pid == client.pid, old.queues == client.queues,
                  client.nanoseconds >= old.nanoseconds else { continue }
            let percent = Double(client.nanoseconds - old.nanoseconds) / (elapsed * 1e9) * 100
            let oldTotal = totals[client.pid]?.1 ?? 0
            totals[client.pid] = (client.name, oldTotal + percent)
        }
        return totals.map { GPUProcessUsage(pid: $0.key, name: $0.value.0, percent: $0.value.1) }
            .sorted { $0.percent == $1.percent ? $0.pid < $1.pid : $0.percent > $1.percent }
            .prefix(8).map { $0 }
    }

    static func parse(_ properties: [String: Any]) -> Client? {
        guard let creator = properties["IOUserClientCreator"] as? String, creator.hasPrefix("pid "),
              let queues = properties["AppUsage"] as? [[String: Any]], !queues.isEmpty else { return nil }
        let fields = creator.dropFirst(4).split(separator: ",", maxSplits: 1)
        guard let raw = fields.first, let pid = Int32(raw.trimmingCharacters(in: .whitespaces)), pid > 0 else { return nil }
        var total: UInt64 = 0
        for queue in queues {
            guard let value = queue["accumulatedGPUTime"] as? NSNumber, value.doubleValue >= 0 else { return nil }
            let addition = total.addingReportingOverflow(value.uint64Value)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return Client(pid: pid, name: fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespaces) : "Process \(pid)",
                      nanoseconds: total, queues: queues.count)
    }

    private static func clients() -> [UInt64: Client] {
        var result: [UInt64: Client] = [:]
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(accelerators) }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                var properties: Unmanaged<CFMutableDictionary>?
                var identifier: UInt64 = 0
                guard result.count < 4_096, IORegistryEntryGetRegistryEntryID(child, &identifier) == KERN_SUCCESS,
                      IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any], let client = parse(values) else { continue }
                result[identifier] = client
            }
        }
        return result
    }
}


/// Kernel counters, sampled only for the Drive page/popup. No per-process subprocesses.
nonisolated final class DriveProcessReader {
    private struct Counter { let name: String; let started: UInt64; let read: UInt64; let written: UInt64 }
    private var previous: [Int32: Counter] = [:]
    private var date: ContinuousClock.Instant?

    func read(at now: ContinuousClock.Instant = .now) -> [DriveProcessUsage] {
        let current = Self.counters()
        defer { previous = current; date = now }
        guard let date else { return [] }
        let elapsed = date.duration(to: now).secondsValue
        guard elapsed > 0, elapsed <= 10 else { return [] }
        return current.compactMap { pid, value in
            guard let old = previous[pid], old.started == value.started, value.read >= old.read, value.written >= old.written else { return nil }
            return DriveProcessUsage(pid: pid, name: value.name, readPerSecond: Double(value.read - old.read) / elapsed,
                                     writePerSecond: Double(value.written - old.written) / elapsed)
        }.sorted {
            let first = $0.readPerSecond + $0.writePerSecond, second = $1.readPerSecond + $1.writePerSecond
            return first == second ? $0.pid < $1.pid : first > second
        }.prefix(8).map { $0 }
    }

    private static func counters() -> [Int32: Counter] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: min(Int(bytes) + 128, 16_384))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [:] }
        var values: [Int32: Counter] = [:]
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard result == 0 else { continue }
            var name = [CChar](repeating: 0, count: 256)
            let length = proc_name(pid, &name, UInt32(name.count))
            values[pid] = Counter(name: length > 0 ? String(cString: name) : "Process \(pid)", started: usage.ri_proc_start_abstime,
                                  read: usage.ri_diskio_bytesread, written: usage.ri_diskio_byteswritten)
        }
        return values
    }
}
