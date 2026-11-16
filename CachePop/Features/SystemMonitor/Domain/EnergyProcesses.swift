import Foundation

nonisolated struct EnergyProcessUsage: Identifiable, Sendable, Equatable {
    let pid: Int32
    let name: String
    /// macOS top's relative POWER score, not watts.
    let impact: Double
    var id: Int32 { pid }
    static func parse(_ output: String) -> [Self] {
        var rows: [Int32: Self] = [:]
        // top prints two samples; keeping the last row for each PID uses its measured interval.
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.first == "PID", fields.contains("POWER") { rows.removeAll(keepingCapacity: true); continue }
            guard fields.count >= 3, let pid = Int32(fields[0]), pid > 0,
                  let impact = Double(fields.last!), impact.isFinite, impact >= 0 else { continue }
            rows[pid] = Self(pid: pid, name: fields.dropFirst().dropLast().joined(separator: " "), impact: impact)
        }
        return Array(rows.values.sorted { $0.impact == $1.impact ? $0.pid < $1.pid : $0.impact > $1.impact }.prefix(8))
    }
}

nonisolated struct MonitorReadRequest: Sendable {
    var processes: Bool
    var details: Bool
    var gpuProcesses = false
    var driveProcesses = false
    var energyProcesses = false
}
