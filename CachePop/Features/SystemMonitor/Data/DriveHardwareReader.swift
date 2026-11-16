import Foundation
import IOKit
import IOKit.storage
import os

nonisolated enum DriveHardwareReader {
    private struct Cached { let date: ContinuousClock.Instant; let health: DriveHealth? }
    private static let cache = OSAllocatedUnfairLock<[String: Cached]>(initialState: [:])

    /// Metadata is off the live sampling path. SMART is read at most once a minute per device;
    /// interfaces are released immediately. Never enables SMART or changes a drive setting.
    static func read() -> [DriveHardware] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [DriveHardware] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard result.count < 32 else { continue }
            var identifier: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &identifier)
            let id = String(identifier)
            let device = property(service, "Device Characteristics") as? [String: Any] ?? [:]
            let protocolInfo = property(service, "Protocol Characteristics") as? [String: Any] ?? [:]
            let model = device["Product Name"] as? String ?? device["Model Number"] as? String ?? "Storage device"
            let connection = protocolInfo["Physical Interconnect"] as? String ?? "Unknown connection"
            guard connection != "Virtual Interface" else { continue }
            let removable = property(service, "Removable") as? Bool ?? false
            let now = ContinuousClock.now
            let cached = cache.withLock { $0[id] }
            let health: DriveHealth?
            if let cached, cached.date.duration(to: now) < .seconds(60) { health = cached.health }
            else {
                health = nvmeHealth(service)
                cache.withLock { $0[id] = Cached(date: now, health: health) }
            }
            result.append(DriveHardware(id: id, model: model.trimmingCharacters(in: .whitespaces), connection: connection,
                                        isRemovable: removable, health: health))
        }
        let current = Set(result.map(\.id))
        cache.withLock { values in values = values.filter { current.contains($0.key) } }
        return result.sorted { $0.id < $1.id }
    }

    private static func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func nvmeHealth(_ service: io_service_t) -> DriveHealth? {
        guard property(service, "NVMe SMART Capable") as? Bool == true else { return nil }
        let clientID = CFUUIDGetConstantUUIDWithBytes(nil, 0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)
        let pluginID = CFUUIDGetConstantUUIDWithBytes(nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
        let interfaceID = CFUUIDGetConstantUUIDWithBytes(nil, 0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)
        var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, clientID, pluginID, &plugin, &score) == KERN_SUCCESS, let plugin else { return nil }
        defer { IODestroyPlugInInterface(plugin) }
        var interface: UnsafeMutablePointer<UnsafeMutablePointer<IONVMeSMARTInterface>?>?
        let result = withUnsafeMutablePointer(to: &interface) { pointer in
            pointer.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
                plugin.pointee?.pointee.QueryInterface(plugin, CFUUIDGetUUIDBytes(interfaceID), $0) ?? KERN_FAILURE
            }
        }
        guard result == KERN_SUCCESS, let interface, let methods = interface.pointee else { return nil }
        defer { _ = methods.pointee.Release(interface) }
        var data = NVMeSMARTData()
        guard methods.pointee.SMARTReadData(interface, &data) == KERN_SUCCESS else { return nil }
        return withUnsafeBytes(of: &data) { DriveHealth.decode(Array($0)) }
    }
}
