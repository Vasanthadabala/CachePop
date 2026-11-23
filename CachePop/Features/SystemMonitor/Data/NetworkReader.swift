import Darwin
import Foundation
import SystemConfiguration

nonisolated enum NetworkReader {
    static func reading() -> NetworkReading? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        let primary = primaryInterface()
        var counters = ByteCounters()
        var interfaces: [String: ByteCounters] = [:]
        var found = false
        var local: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            let name = String(cString: entry.ifa_name)
            if let address = entry.ifa_addr {
                if address.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
                   let bytes = interfaceBytes(name) {
                    interfaces[name] = bytes
                    counters.read = NetworkReading.add(counters.read, bytes.read)
                    counters.written = NetworkReading.add(counters.written, bytes.written)
                    found = true
                }
                if name == primary, entry.ifa_flags & UInt32(IFF_UP) != 0,
                   address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        if local == nil || address.pointee.sa_family == UInt8(AF_INET) { local = String(cString: host) }
                    }
                }
            }
            pointer = entry.ifa_next
        }
        guard found else { return nil }
        return NetworkReading(counters: counters, interface: primary, localAddress: local, interfaceCounters: interfaces)
    }

    private static func interfaceBytes(_ name: String) -> ByteCounters? {
        let index = if_nametoindex(name)
        guard index > 0, index <= Int32.max else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        // getifaddrs' if_data byte fields are 32-bit; use the SDK's 64-bit counters
        // so sustained transfers do not wrap every few gigabytes.
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return nil }
        return ByteCounters(read: data.ifmd_data.ifi_ibytes, written: data.ifmd_data.ifi_obytes)
    }

    private static func primaryInterface() -> String? {
        for family in ["IPv4", "IPv6"] {
            if let state = SCDynamicStoreCopyValue(nil, "State:/Network/Global/\(family)" as CFString) as? [String: Any],
               let interface = state["PrimaryInterface"] as? String { return interface }
        }
        return nil
    }
}
