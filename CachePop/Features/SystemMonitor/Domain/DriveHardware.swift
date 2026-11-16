import Foundation

nonisolated struct DriveHealth: Sendable, Equatable {
    let remainingLife: Int
    let temperature: Double?
    let totalRead: Int64
    let totalWritten: Int64
    let powerCycles: UInt64
    let powerOnHours: UInt64
    let unsafeShutdowns: UInt64
    let mediaErrors: UInt64
    let criticalWarning: UInt8
    let availableSpare: UInt8
    var isWarning: Bool { criticalWarning != 0 || remainingLife < 10 || mediaErrors > 0 }

    /// NVMe SMART/Health log (NVM Express, log page 02h), little endian, 512-byte data units.
    static func decode(_ bytes: [UInt8]) -> DriveHealth? {
        guard bytes.count >= 192 else { return nil }
        func counter(_ offset: Int) -> UInt64 {
            guard bytes[(offset + 8)..<(offset + 16)].allSatisfy({ $0 == 0 }) else { return .max }
            return bytes[offset..<(offset + 8)].enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        func transferred(_ offset: Int) -> Int64 {
            let count = counter(offset).multipliedReportingOverflow(by: 512_000)
            return count.overflow || count.partialValue > UInt64(Int64.max) ? .max : Int64(count.partialValue)
        }
        let celsius = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8) - 273.15
        return DriveHealth(remainingLife: max(100 - Int(bytes[5]), 0), temperature: (1...130).contains(celsius) ? celsius : nil,
                           totalRead: transferred(32), totalWritten: transferred(48), powerCycles: counter(112),
                           powerOnHours: counter(128), unsafeShutdowns: counter(144), mediaErrors: counter(160),
                           criticalWarning: bytes[0], availableSpare: bytes[3])
    }
}


nonisolated struct DriveHardware: Sendable, Equatable, Identifiable {
    let id: String
    let model: String
    let connection: String
    let isRemovable: Bool
    let health: DriveHealth?
}
