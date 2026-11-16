import Darwin
import Foundation
import IOKit
import DiskArbitration

nonisolated enum GPUReader {
    /// Driver statistics are optional and vary by GPU and macOS version.
    static func read() -> [GPUSample] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [GPUSample] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            var identifier: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &identifier)
            let rawName = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            let name = rawName as? String ?? (rawName as? Data).flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) } ?? "Graphics processor"
            result.append(GPUSample(id: String(identifier), name: name,
                                    utilization: GPUSample.percentage(statistics["Device Utilization %"] as? NSNumber ?? statistics["GPU Activity(%)"] as? NSNumber),
                                    renderer: GPUSample.percentage(statistics["Renderer Utilization %"] as? NSNumber),
                                    tiler: GPUSample.percentage(statistics["Tiler Utilization %"] as? NSNumber),
                                    memoryBytes: (statistics["In use system memory"] as? NSNumber).flatMap { $0.int64Value >= 0 ? $0.int64Value : nil }))
        }
        return result.sorted { $0.id < $1.id }
    }
}


extension CPUCoreTopology {
    static func read() -> [Int: CPUCoreKind] {
        let parent = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard parent != 0 else { return [:] }
        defer { IOObjectRelease(parent) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(parent, "IODeviceTree", &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var kinds: [Int: CPUCoreKind] = [:]
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard let index = IORegistryEntryCreateCFProperty(child, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
                  let data = IORegistryEntryCreateCFProperty(child, "cluster-type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  let letter = data.first else { continue }
            if letter == 69 { kinds[index.intValue] = .efficiency }
            if letter == 80 { kinds[index.intValue] = .performance }
        }
        return kinds
    }

}

nonisolated enum MonitorEnvironmentReader {
    static func read() -> MonitorEnvironment {
        MonitorEnvironment(volumes: volumes(), hasLoaded: true, hardware: DriveHardwareReader.read())
    }

    /// MNT_NOWAIT uses cached mount information: external drives never block live sampling.
    static func volumes() -> [MountedVolume] {
        let session = DASessionCreate(kCFAllocatorDefault)
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var entries = Array<Darwin.statfs>(repeating: Darwin.statfs(), count: min(Int(count) + 8, 512))
        let bytes = Int32(entries.count * MemoryLayout<statfs>.stride)
        let actual = entries.withUnsafeMutableBufferPointer { getfsstat($0.baseAddress, bytes, MNT_NOWAIT) }
        guard actual > 0 else { return [] }
        return entries.prefix(min(Int(actual), entries.count)).compactMap { entry in
            var entry = entry
            let path = withUnsafePointer(to: &entry.f_mntonname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            guard entry.f_flags & UInt32(MNT_LOCAL) != 0, path == "/" || path.hasPrefix("/Volumes/"),
                  entry.f_flags & UInt32(MNT_DONTBROWSE) == 0 || path == "/" else { return nil }
            let format = withUnsafePointer(to: &entry.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) { String(cString: $0) } }
            let block = UInt64(entry.f_bsize)
            func capacity(_ blocks: UInt64) -> Int64 {
                let value = blocks.multipliedReportingOverflow(by: block)
                return value.overflow || value.partialValue > UInt64(Int64.max) ? Int64.max : Int64(value.partialValue)
            }
            var driverID: String?
            var encrypted: Bool?
            if let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: path) as CFURL) {
                let description = DADiskCopyDescription(disk) as? [String: Any]
                encrypted = description?[kDADiskDescriptionMediaEncryptedKey as String] as? Bool
                var service = DADiskCopyIOMedia(disk)
                var visited = 0
                while service != 0, visited < 32 {
                    if IOObjectConformsTo(service, "IOBlockStorageDriver") != 0 {
                        var identifier: UInt64 = 0
                        IORegistryEntryGetRegistryEntryID(service, &identifier)
                        driverID = String(identifier)
                        IOObjectRelease(service)
                        break
                    }
                    var parent: io_registry_entry_t = 0
                    let status = IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)
                    IOObjectRelease(service)
                    guard status == KERN_SUCCESS else { break }
                    service = parent
                    visited += 1
                    if visited == 32 { IOObjectRelease(service) }
                }
            }
            let device = withUnsafePointer(to: &entry.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
            return MountedVolume(id: path, name: path == "/" ? "Startup disk" : URL(fileURLWithPath: path).lastPathComponent,
                                 format: format.uppercased(), total: capacity(entry.f_blocks), available: capacity(entry.f_bavail),
                                 isReadOnly: entry.f_flags & UInt32(MNT_RDONLY) != 0, bsdName: device.hasPrefix("/dev/") ? String(device.dropFirst(5)) : nil,
                                 driverID: driverID, isEncrypted: encrypted)
        }.sorted { $0.id < $1.id }
    }
}
