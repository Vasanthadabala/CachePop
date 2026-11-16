import Foundation

nonisolated struct PerformanceSample: Sendable, Equatable {
    var efficiencyMHz: Double?
    var performanceMHz: Double?
    var cpuWatts: Double?
    var gpuWatts: Double?
    var neuralWatts: Double?
    var memoryWatts: Double?
    /// Compositor swaps summed across reporting displays; this is not an individual game's FPS.
    var displayFramesPerSecond: Double?

    func cpuMHz(efficiencyCores: Int, performanceCores: Int) -> Double? {
        let values = [(efficiencyMHz, efficiencyCores), (performanceMHz, performanceCores)].compactMap { value, cores -> (Double, Int)? in
            guard let value, value.isFinite, value > 0, cores > 0 else { return nil }
            return (value, cores)
        }
        let count = values.reduce(0) { $0 + $1.1 }
        return count > 0 ? values.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(count) : nil
    }
}
