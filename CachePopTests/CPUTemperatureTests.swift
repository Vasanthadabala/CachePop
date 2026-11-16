import Foundation
import Testing
@testable import CachePop

@Suite("CPU temperature accuracy")
struct CPUTemperatureTests {
    @Test func powerManagementAndGPUSensorsAreNotCPUTemperature() {
        let sample = TemperatureSample.from([("PMU tdie1", 35), ("PMU2 tdie1", 34), ("GPU die", 80)])
        #expect(sample.chip == nil)
        #expect(sample.chipMax == nil)
        #expect(sample.sensors.map(\.group) == [.other, .other, .gpu])
    }

    @Test func HIDFallbackUsesOnlyValidCPUSensors() {
        let sample = TemperatureSample.from([
            ("pACC MTR Temp Sensor0", 60), ("eACC MTR Temp Sensor0", 40),
            ("CPU core", 50), ("CPU offline", 2), ("CPU broken", 121),
            ("PMU tdie1", 30), ("GPU die", 90)
        ])
        #expect(sample.chip == 50)
        #expect(sample.chipMax == 60)
    }

    @Test func M4SelectionExcludesGPUAndOtherGenerationKeys() {
        let keys = ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        let selected = CPUTemperature.sensors(chipName: "Apple M4", availableKeys: keys + ["Tg0G", "Tm0B", "Tp1h", "Tp00", "TC0P"])
        #expect(selected.map(\.key) == keys)
        #expect(Set(selected.map(\.key)).count == selected.count)
    }

    @Test func sensorMapsFollowTheChipGenerationAndAvailableKeys() {
        let keys = ["Tp09", "Tp0T", "Tp1h", "Te05", "Tf04", "Tp00", "Tg0G"]
        #expect(CPUTemperature.sensors(chipName: "Apple M1 Pro", availableKeys: keys).map(\.key) == ["Tp09", "Tp0T"])
        #expect(CPUTemperature.sensors(chipName: "Apple M2 Max", availableKeys: keys).map(\.key) == ["Tp1h", "Tp09"])
        #expect(CPUTemperature.sensors(chipName: "Apple M3", availableKeys: keys).map(\.key) == ["Te05", "Tf04"])
        #expect(CPUTemperature.sensors(chipName: "Apple M4 Pro", availableKeys: keys).map(\.key) == ["Te05", "Tp09"])
        #expect(CPUTemperature.sensors(chipName: "Apple M5", availableKeys: keys).map(\.key) == ["Tp00"])
        #expect(CPUTemperature.sensors(chipName: "Apple M10", availableKeys: keys).isEmpty)
        #expect(CPUTemperature.sensors(chipName: "Apple M4", availableKeys: []).isEmpty)
    }

    @Test func cpuAverageAndSafetyMaximumUseTheSameValidCoreReadings() throws {
        let values: [String: Double] = ["Te05": 48, "Te09": 50, "Tp01": 60, "Tp05": 62]
        let sensors = CPUTemperature.sensors(chipName: "Apple M4", availableKeys: Array(values.keys))
        let reading = try #require(CPUTemperature.read(sensors) { values[$0] })
        #expect(reading.average == 55)
        #expect(reading.maximum == 62)
        var sample = TemperatureSample.from([("PMU tdie1", 35), ("NAND", 37), ("battery", 31)])
        sample.applyCPU(reading)
        #expect(sample.chip == 55)
        #expect(sample.chipMax == 62)
        #expect(sample.ssd == 37 && sample.battery == 31)
        #expect(sample.sensors.filter { $0.group == .cpu }.count == 4)
        #expect(Set(sample.sensors.map(\.id)).count == sample.sensors.count)
    }

    @Test func parkedMissingAndNonfiniteReadingsCannotPullDownTheAverage() throws {
        let values: [String: Double] = ["Te05": 40, "Te09": 2.1, "Te0H": .nan, "Te0S": .infinity, "Tp01": 60, "Tp05": 0, "Tp09": 121]
        let sensors = CPUTemperature.sensors(chipName: "Apple M4", availableKeys: Array(values.keys) + ["Tp0D"])
        let reading = try #require(CPUTemperature.read(sensors) { values[$0] })
        #expect(reading.average == 50)
        #expect(reading.maximum == 60)
        #expect(reading.sensors.map(\.celsius) == [40, 60])
        #expect(CPUTemperature.read(sensors) { _ in 0 } == nil)
        #expect(CPUTemperature.read(sensors) { _ in nil } == nil)
    }

    @Test func freshUnavailableReadingsDoNotReuseAnOldOrUnrelatedTemperature() {
        var sample = TemperatureSample.from([("PMU tdie1", 36), ("GPU die", 70)])
        sample.applyCPU(nil)
        #expect(sample.chip == nil && sample.chipMax == nil)
    }

    @Test func hotterValidHIDCPUReadingsStillProtectFanSafety() throws {
        let descriptors = [CPUTemperature.Sensor(key: "Tp01", name: "CPU sensor")]
        let reading = try #require(CPUTemperature.read(descriptors) { _ in 60 })
        var sample = TemperatureSample.from([("CPU core", 98), ("PMU tdie1", 110)])
        sample.applyCPU(reading)
        #expect(sample.chip == 60)
        #expect(sample.chipMax == 98)
    }

    @Test func intelPrefersTheCPUDieAndFallsBackToCoresWithoutIncludingIntegratedGPU() throws {
        let values: [String: Double] = ["TC0D": 48, "TC0F": 47, "TC0c": 60, "TC1C": 58, "TCGC": 90, "TC0P": 30]
        let descriptors = CPUTemperature.sensors(chipName: "Intel(R) Core(TM) i7", availableKeys: Array(values.keys))
        #expect(!descriptors.contains { $0.key == "TCGC" || $0.key == "TC0P" })
        let reading = try #require(CPUTemperature.read(descriptors) { values[$0] })
        #expect(reading.average == 48 && reading.maximum == 60)
        let fallback = try #require(CPUTemperature.read(descriptors) { $0 == "TC0c" ? 60 : nil })
        #expect(fallback.average == 60)
    }

    @Test func intelTemperatureFormatDecodesSignedFixedPointValues() {
        #expect(SMC.decode(type: "sp78", bytes: [0x2a, 0x80]) == 42.5)
        #expect(SMC.decode(type: "sp78", bytes: [0xf5, 0x80]) == -10.5)
        #expect(SMC.decode(type: "sp78", bytes: [0]) == nil)
        #expect(SMC.decode(type: "sp78", bytes: [0x78, 0]) == 120)
    }
}
