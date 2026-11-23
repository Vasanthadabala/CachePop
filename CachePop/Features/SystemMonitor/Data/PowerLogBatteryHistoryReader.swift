import Foundation

/// Best-effort recovery of charge observations in macOS's power-event log.
/// This log is sparse: it is not System Settings' private, continuous battery database.
nonisolated struct PowerLogBatteryHistoryReader: BatteryChargeHistoryReading {
    let runner: any CommandRunning

    init(runner: any CommandRunning = ProcessCommandRunner(stopsWhenCancelled: true, maximumOutputBytes: 33_554_432)) {
        self.runner = runner
    }

    @concurrent
    func readings(in interval: DateInterval) async -> [BatteryChargeReading] {
        let command = ToolCommand(executable: URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["-g", "log"],
                                  environment: ["LC_ALL": "C"])
        guard let output = try? await runner.run(command, timeout: 20), output.succeeded,
              !Task.isCancelled else { return [] }
        return Self.parse(output.stdout, in: interval)
    }

    static func parse(_ output: String, in interval: DateInterval) -> [BatteryChargeReading] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.isLenient = false
        var values: [BatteryChargeReading] = []
        for line in output.split(separator: "\n") {
            guard let charge = line.range(of: "Charge:"), line.count >= 25,
                  let date = formatter.date(from: String(line.prefix(25))),
                  date >= interval.start, date <= interval.end else { continue }
            let suffix = line[charge.upperBound...].drop(while: { $0.isWhitespace })
            let digits = suffix.prefix(while: { $0.isASCII && $0.isNumber })
            guard suffix.dropFirst(digits.count).first == "%",
                  let percent = Int(digits), (0...100).contains(percent) else { continue }
            values.append(BatteryChargeReading(date: date, percent: percent))
        }
        return values.sorted { $0.date < $1.date }
    }
}
