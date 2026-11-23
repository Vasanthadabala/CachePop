import Foundation

/// Physical Wi-Fi and Ethernet interface counters. VPN traffic is already included by its
/// underlying interface, so virtual tunnel counters must not be added a second time.
nonisolated struct NetworkReading: Sendable, Equatable {
    var counters: ByteCounters
    var interface: String?
    var localAddress: String?
    var interfaceCounters: [String: ByteCounters] = [:]

    /// Compare each physical interface independently so reconnects cannot produce spikes.
    func bytes(since previous: Self) -> ByteCounters {
        let current = interfaceCounters.isEmpty ? ["aggregate": counters] : interfaceCounters
        let earlier = previous.interfaceCounters.isEmpty ? ["aggregate": previous.counters] : previous.interfaceCounters
        return current.reduce(into: ByteCounters()) { total, pair in
            guard let old = earlier[pair.key] else { return }
            let read = pair.value.read >= old.read ? pair.value.read - old.read : 0
            let written = pair.value.written >= old.written ? pair.value.written - old.written : 0
            total.read = Self.add(total.read, read)
            total.written = Self.add(total.written, written)
        }
    }

    static func add(_ first: UInt64, _ second: UInt64) -> UInt64 {
        let result = first.addingReportingOverflow(second)
        return result.overflow ? .max : result.partialValue
    }
}
