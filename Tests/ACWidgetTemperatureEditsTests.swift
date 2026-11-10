import Foundation
import Testing
@testable import BreezePilot

struct ACWidgetTemperatureEditsTests {
    @Test func repeatedTapsFromOneWidgetReadingWriteOnlyTheFinalTemperature() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let edits = ACWidgetTemperatureEdits(directory: directory, quietPeriod: 0)
        let unit = UUID()
        let device = TemperatureDevice(target: 52)

        for _ in 0..<6 {
            try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)
        }
        #expect(await device.writes.isEmpty)

        let status = await edits.applyPending(for: unit, device: device, waitForReadback: {})

        #expect(status?.target == 58)
        #expect(await device.writes == [58])
        #expect(await edits.applyPending(for: unit, device: device, waitForReadback: {}) == nil)
    }

    @Test func oppositeTapsCancelAndRepeatedTapsRespectTheTemperatureLimit() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let edits = ACWidgetTemperatureEdits(directory: directory, quietPeriod: 0)
        let unit = UUID()
        let device = TemperatureDevice(target: 58)
        try edits.enqueue(for: unit, previous: 58, target: 59, mode: .cool, limits: 36...60)
        try edits.enqueue(for: unit, previous: 58, target: 57, mode: .cool, limits: 36...60)

        #expect(await edits.applyPending(for: unit, device: device, waitForReadback: {}) == nil)
        for _ in 0..<4 {
            try edits.enqueue(for: unit, previous: 58, target: 59, mode: .cool, limits: 36...60)
        }
        _ = await edits.applyPending(for: unit, device: device, waitForReadback: {})
        #expect(await device.writes == [60])
    }

    @Test func aFreshWidgetReadingCanStartFromAnExternallyChangedTemperature() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let edits = ACWidgetTemperatureEdits(directory: directory, quietPeriod: 0)
        let unit = UUID()
        let device = TemperatureDevice(target: 52)
        try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)
        _ = await edits.applyPending(for: unit, device: device, waitForReadback: {})
        await device.setExternally(to: 56)

        try edits.enqueue(for: unit, previous: 56, target: 57, mode: .cool,
                          limits: 36...60, observedAt: .now)
        _ = await edits.applyPending(for: unit, device: device, waitForReadback: {})

        #expect(await device.writes == [53, 57])
    }

    @Test func queuedTapsDoNotOverwriteAnExternalChangeAfterTheWidgetReading() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let edits = ACWidgetTemperatureEdits(directory: directory, quietPeriod: 0)
        let unit = UUID()
        let device = TemperatureDevice(target: 56)
        try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)
        try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)

        #expect(await edits.applyPending(for: unit, device: device, waitForReadback: {}) == nil)
        #expect(await device.writes.isEmpty)
        #expect(await edits.applyPending(for: unit, device: device, waitForReadback: {}) == nil)
    }

    @Test func tapsDuringReadbackAreAppliedAgainstTheConfirmedTarget() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let edits = ACWidgetTemperatureEdits(directory: directory, quietPeriod: 0)
        let unit = UUID()
        let device = TemperatureDevice(target: 52)
        try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)

        let status = await edits.applyPending(for: unit, device: device) {
            if await device.writes == [53] {
                try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)
                try edits.enqueue(for: unit, previous: 52, target: 53, mode: .cool, limits: 36...60)
            }
        }

        #expect(status?.target == 55)
        #expect(await device.writes == [53, 55])
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor TemperatureDevice: ACDevice {
    private var target: Int
    private(set) var writes: [Int] = []

    init(target: Int) { self.target = target }

    func setExternally(to target: Int) { self.target = target }

    func readStatus() throws -> ACStatus {
        ACStatus(isOn: true, mode: .cool, availableModes: [.cool],
                 room: RoomConditions(temperature: nil, humidity: nil), target: target, limits: 36...60,
                 fan: nil, features: ACFeatures(boost: nil, econo: nil, streamer: nil))
    }

    func write(_ change: ACChange, current: ACStatus) throws {
        guard case let .target(target, _, _) = change else { throw ACDeviceError.unexpectedResponse }
        self.target = target
        writes.append(target)
    }
}
