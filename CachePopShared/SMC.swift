import Foundation
import IOKit

/// Talks to the System Management Controller. Anyone can read keys; only root can write them.
nonisolated final class SMC: @unchecked Sendable {
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PowerLimits { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0 }
    /// Padded to 12 bytes to match the C struct; Swift would otherwise pack the next fields into it.
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attributes: UInt8 = 0; var padding: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Message {
        var key: UInt32 = 0
        var version = Version()
        var limits = PowerLimits()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let readKeyCommand: UInt8 = 5
    private static let writeKeyCommand: UInt8 = 6
    private static let keyAtIndexCommand: UInt8 = 8
    private static let readKeyInfoCommand: UInt8 = 9
    private static let handleEvent: UInt32 = 2

    private var connection: io_connect_t = 0
    private let lock = NSLock()
    /// Each key's type and size, looked up once: they never change, and asking again doubled
    /// the SMC calls of every reading. Only keys that exist are kept, so a failed lookup is retried.
    private var infoCache: [UInt32: (type: String, size: UInt32)] = [:]

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    var isAvailable: Bool { connection != 0 }

    /// The key's type ("flt ", "ui8 ", "fpe2"…) and size, or nil when the key doesn't exist.
    func info(_ key: String) -> (type: String, size: UInt32)? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return unlockedInfo(key)
    }

    /// The key's type and raw bytes, or nil when the key doesn't exist.
    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let info = unlockedInfo(key) else { return nil }

        var request = Message()
        request.key = Self.fourCharacterCode(key)
        request.info.dataSize = info.size
        request.command = Self.readKeyCommand
        guard let value = call(&request) else { return nil }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(min(info.size, 32)))) }
        return (info.type, bytes)
    }

    /// Writes raw bytes to an existing key. Fails unless the process runs as root.
    @discardableResult
    func write(_ key: String, bytes: [UInt8]) -> Bool {
        guard connection != 0, key.utf8.count == 4, !bytes.isEmpty, bytes.count <= 32 else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let info = unlockedInfo(key), Int(info.size) == bytes.count else { return false }

        var request = Message()
        request.key = Self.fourCharacterCode(key)
        request.info.dataSize = info.size
        request.command = Self.writeKeyCommand
        withUnsafeMutableBytes(of: &request.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return call(&request) != nil
    }

    func number(_ key: String) -> Double? {
        guard let value = read(key) else { return nil }
        return Self.decode(type: value.type, bytes: value.bytes)
    }

    /// Every key this Mac's SMC has, to find which sensors it reports. Thousands of calls: look
    /// once and keep the answer.
    func allKeys() -> [String] {
        guard let count = number("#KEY"), count > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return (0..<UInt32(min(count, 10_000))).compactMap { index in
            var request = Message()
            request.command = Self.keyAtIndexCommand
            request.data32 = index
            guard let key = call(&request)?.key else { return nil }
            return String(bytes: withUnsafeBytes(of: key.bigEndian) { Array($0) }, encoding: .ascii)
        }
    }

    var fanCount: Int {
        guard let count = number("FNum"), count.isFinite, count > 0 else { return 0 }
        return Int(min(count, 8))
    }

    /// Fans with their current, minimum and maximum speeds. Empty on Macs without fans.
    func fans() -> [FanSample] {
        (0..<min(fanCount, 8)).compactMap { index in
            guard let rpm = number("F\(index)Ac") else { return nil }
            return FanSample(index: index, rpm: rpm, minimum: number("F\(index)Mn") ?? 0, maximum: number("F\(index)Mx") ?? 0)
        }
    }

    /// The type of each fan-control key that exists on this Mac, for `FanWritePlan`.
    func fanKeyTypes(fan: Int) -> [String: String] {
        var types: [String: String] = [:]
        for key in ["Ftst", "FS! ", "F\(fan)Md", "F\(fan)Tg"] {
            if let info = info(key) { types[key] = info.type }
        }
        return types
    }

    private func unlockedInfo(_ key: String) -> (type: String, size: UInt32)? {
        let code = Self.fourCharacterCode(key)
        if let cached = infoCache[code] { return cached }
        var request = Message()
        request.key = code
        request.command = Self.readKeyInfoCommand
        guard let info = call(&request), info.info.dataSize > 0 else { return nil }
        let type = String(bytes: withUnsafeBytes(of: info.info.dataType.bigEndian) { Array($0) }, encoding: .ascii) ?? ""
        infoCache[code] = (type, info.info.dataSize)
        return (type, info.info.dataSize)
    }

    private func call(_ input: inout Message) -> Message? {
        var output = Message()
        var size = MemoryLayout<Message>.stride
        let result = IOConnectCallStructMethod(connection, Self.handleEvent, &input, MemoryLayout<Message>.stride, &output, &size)
        return result == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    static func fourCharacterCode(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    // MARK: Number formats

    /// Little-endian floats on Apple silicon, fixed point on Intel.
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "sp78" where bytes.count >= 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "flt " where bytes.count >= 4:
            let value = Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
            return value.isFinite ? value : nil
        case "fpe2" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 " where bytes.count >= 1:
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count >= 4:
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }

    static func encode(_ value: Double, type: String) -> [UInt8]? {
        guard value.isFinite else { return nil }
        switch type {
        case "flt ":
            guard Float(value).isFinite else { return nil }
            let bits = Float(value).bitPattern
            return [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24 & 0xFF)]
        case "fpe2":
            let bounded = min(max(value, 0), Double(UInt16.max) / 4)
            let fixed = UInt16((bounded * 4).rounded())
            return [UInt8(fixed >> 8), UInt8(fixed & 0xFF)]
        case "ui8 ":
            return [UInt8(min(max(value, 0), Double(UInt8.max)).rounded())]
        case "ui16":
            let number = UInt16(min(max(value, 0), Double(UInt16.max)).rounded())
            return [UInt8(number >> 8), UInt8(number & 0xFF)]
        default:
            return nil
        }
    }
}

// MARK: - Fan control plan


/// One SMC key write.
nonisolated struct SMCWrite: Sendable, Equatable {
    let key: String
    let bytes: [UInt8]
}


/// Works out which SMC keys to write to set or release a fan. Pure, so it can be tested on any Mac.
///
/// Apple silicon: unlock with `Ftst` = 1, put the fan in manual mode with `F<n>Md` = 1, then set
/// the target `F<n>Tg`. Older Intel Macs use the `FS! ` bit mask instead of `F<n>Md`.
nonisolated enum FanWritePlan {
    /// Never below the minimum macOS allows, never above the maximum.
    static func clamp(_ rpm: Double, minimum: Double, maximum: Double) -> Double {
        min(max(rpm, minimum), max(maximum, minimum))
    }

    /// Writes for a fixed speed, or nil when this Mac doesn't expose the keys needed.
    static func manual(fan: Int, rpm: Double, minimum: Double, maximum: Double,
                       keyTypes: [String: String], forcedMask: UInt16? = nil) -> [SMCWrite]? {
        guard (0..<16).contains(fan), rpm.isFinite, minimum.isFinite, maximum.isFinite,
              minimum >= 0, maximum > 0, maximum >= minimum, let targetType = keyTypes["F\(fan)Tg"],
              let target = SMC.encode(clamp(rpm, minimum: minimum, maximum: maximum), type: targetType) else { return nil }

        var writes: [SMCWrite] = []
        if keyTypes["Ftst"] != nil { writes.append(SMCWrite(key: "Ftst", bytes: [1])) }
        if let modeType = keyTypes["F\(fan)Md"], let manual = SMC.encode(1, type: modeType) {
            writes.append(SMCWrite(key: "F\(fan)Md", bytes: manual))
        } else if keyTypes["FS! "] != nil {
            let mask = (forcedMask ?? 0) | UInt16(1) << UInt16(fan)
            writes.append(SMCWrite(key: "FS! ", bytes: [UInt8(mask >> 8), UInt8(mask & 0xFF)]))
        } else {
            return nil
        }
        writes.append(SMCWrite(key: "F\(fan)Tg", bytes: target))
        return writes
    }

    /// Writes that hand the fan back to macOS. `othersManual` keeps the unlock while other fans
    /// are still on a fixed speed.
    static func automatic(fan: Int, othersManual: Bool, keyTypes: [String: String], forcedMask: UInt16? = nil) -> [SMCWrite] {
        guard (0..<16).contains(fan) else { return [] }
        var writes: [SMCWrite] = []
        if let modeType = keyTypes["F\(fan)Md"], let auto = SMC.encode(0, type: modeType) {
            writes.append(SMCWrite(key: "F\(fan)Md", bytes: auto))
        } else if keyTypes["FS! "] != nil {
            let mask = (forcedMask ?? 0) & ~(UInt16(1) << UInt16(fan))
            writes.append(SMCWrite(key: "FS! ", bytes: [UInt8(mask >> 8), UInt8(mask & 0xFF)]))
        }
        if !othersManual, keyTypes["Ftst"] != nil { writes.append(SMCWrite(key: "Ftst", bytes: [0])) }
        return writes
    }
}
