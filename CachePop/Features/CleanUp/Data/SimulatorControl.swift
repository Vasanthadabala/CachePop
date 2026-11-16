import Foundation

/// Thin wrapper around `simctl`. Reading is always safe; the cleaner only issues the
/// erase/delete commands after re-checking that the target isn't booted.
nonisolated struct SimulatorControl: Sendable {
    let simctl: URL
    let runner: any CommandRunning

    typealias DeviceSet = SimulatorDeviceSet

    func command(_ arguments: [String], set: DeviceSet = .standard) -> ToolCommand {
        ToolCommand(executable: simctl, arguments: set.arguments + arguments)
    }

    func devices(in set: DeviceSet = .standard) async throws -> [SimulatorDevice] {
        let output = try await runner.run(command(["list", "devices", "-j"], set: set), timeout: 60)
        guard output.succeeded else { throw CommandError.launchFailed(output.failureSummary) }
        return try Self.parseDevices(Data(output.stdout.utf8))
    }

    func runtimeImages() async throws -> [SimulatorRuntimeImage] {
        let output = try await runner.run(command(["runtime", "list", "-j"]), timeout: 60)
        guard output.succeeded else { throw CommandError.launchFailed(output.failureSummary) }
        return try Self.parseRuntimeImages(Data(output.stdout.utf8))
    }

    // MARK: Parsing

    static func parseDevices(_ data: Data) throws -> [SimulatorDevice] {
        nonisolated struct Listing: Decodable { let devices: [String: [SimulatorDevice]] }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        return listing.devices
            .flatMap { runtime, devices in
                devices.map { device in
                    var device = device
                    device.runtimeIdentifier = runtime
                    return device
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parseRuntimeImages(_ data: Data) throws -> [SimulatorRuntimeImage] {
        let listing = try JSONDecoder().decode([String: SimulatorRuntimeImage].self, from: data)
        return listing.values.sorted { ($0.version ?? "") < ($1.version ?? "") }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-0" → "iOS 27.0".
    static func runtimeName(_ identifier: String) -> String {
        guard let marker = identifier.range(of: "SimRuntime.", options: .backwards) else { return identifier }
        let parts = identifier[marker.upperBound...].split(separator: "-").map(String.init)
        guard let platform = parts.first else { return identifier }
        let displayPlatform = platform == "xrOS" ? "visionOS" : platform
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? displayPlatform : "\(displayPlatform) \(version)"
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

/// `brew cleanup --dry-run` ends with "This operation would free approximately 1.2GB of disk
/// space." Homebrew's units are 1024-based.
nonisolated enum HomebrewOutput {
    static func reclaimableBytes(fromDryRun output: String) -> Int64 {
        if let summary = firstMatch(in: output, pattern: #"free approximately ([0-9.]+)\s*([KMGT]?B)"#) {
            return bytes(summary.0, summary.1)
        }

        // Older versions only list "Would remove: … (12.3MB)" lines.
        let regex = try? NSRegularExpression(pattern: #"Would remove:.*\(([0-9.]+)\s*([KMGT]?B)\)"#)
        let range = NSRange(output.startIndex..., in: output)
        return (regex?.matches(in: output, range: range) ?? []).reduce(Int64(0)) { total, match in
            guard let numberRange = Range(match.range(at: 1), in: output),
                  let unitRange = Range(match.range(at: 2), in: output) else { return total }
            return total + bytes(String(output[numberRange]), String(output[unitRange]))
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[numberRange]), String(text[unitRange]))
    }

    private static func bytes(_ number: String, _ unit: String) -> Int64 {
        guard let value = Double(number) else { return 0 }
        let multiplier: Double = switch unit.uppercased() {
        case "KB": 1_024
        case "MB": 1_048_576
        case "GB": 1_073_741_824
        case "TB": 1_099_511_627_776
        default:   1
        }
        return Int64(value * multiplier)
    }
}
