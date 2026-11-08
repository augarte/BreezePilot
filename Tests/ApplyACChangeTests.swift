import Foundation
import Testing
@testable import BreezePilot

struct ApplyACChangeTests {
    @Test func skipsWriteWhenDeviceAlreadyHasTheRequestedSetting() async throws {
        let device = ScriptedDevice(reads: [sampleStatus(target: 52)])
        let apply = ApplyACChange(device: device, waitForReadback: {})

        let result = try await apply(.target(52, previous: 54, mode: .cool))

        #expect(result.status?.target == 52)
        #expect(result.message == nil)
        #expect(await device.writes.isEmpty)
        #expect(await device.readCount == 1)
    }

    @Test func skipsWriteWhenAnExternalChangeMadeTheDraftStale() async throws {
        let device = ScriptedDevice(reads: [sampleStatus(target: 56)])
        let apply = ApplyACChange(device: device, waitForReadback: {})

        let result = try await apply(.target(52, previous: 54, mode: .cool))

        #expect(result.status?.target == 56)
        #expect(result.message != nil)
        #expect(await device.writes.isEmpty)
    }

    @Test func skipsWriteWhenCurrentModeOrStepDoesNotAllowIt() async throws {
        let device = ScriptedDevice(reads: [sampleStatus(mode: .fan), sampleStatus(step: 2)])
        let apply = ApplyACChange(device: device, waitForReadback: {})

        let modeResult = try await apply(.target(52, previous: 54, mode: .cool))
        let stepResult = try await apply(.target(53, previous: 54, mode: .cool))

        #expect(modeResult.message != nil)
        #expect(stepResult.message != nil)
        #expect(await device.writes.isEmpty)
    }

    @Test func confirmsAfterLostAcknowledgementAndFailedReadWithoutRewriting() async throws {
        let device = ScriptedDevice(
            reads: [sampleStatus(), nil, sampleStatus(), sampleStatus(target: 52)],
            writeError: .unreachable
        )
        let apply = ApplyACChange(device: device, waitForReadback: {})

        let result = try await apply(.target(52, previous: 54, mode: .cool))

        #expect(result.status?.target == 52)
        #expect(result.message == nil)
        #expect(await device.readCount == 4)
        let writes = await device.writes
        #expect(writes.count == 1)
        guard case let .target(target, previous, mode) = try #require(writes.first) else {
            Issue.record("Expected a temperature write")
            return
        }
        #expect(target == 52)
        #expect(previous == 54)
        #expect(mode == .cool)
    }

    @Test func returnsLatestKnownStatusAfterReadbackAttemptsAreExhausted() async throws {
        let device = ScriptedDevice(reads: [sampleStatus(), nil, sampleStatus(target: 56), nil, nil])
        let apply = ApplyACChange(device: device, waitForReadback: {})

        let result = try await apply(.target(52, previous: 54, mode: .cool))

        #expect(result.status?.target == 56)
        #expect(result.message == ACDeviceError.unconfirmed.localizedDescription)
        #expect(await device.writes.count == 1)
        #expect(await device.readCount == 5)
    }
}

private actor ScriptedDevice: ACDevice {
    private var reads: ArraySlice<ACStatus?>
    private let writeError: ACDeviceError?
    private(set) var readCount = 0
    private(set) var writes: [ACChange] = []

    init(reads: [ACStatus?], writeError: ACDeviceError? = nil) {
        self.reads = reads[...]
        self.writeError = writeError
    }

    func readStatus() async throws -> ACStatus {
        readCount += 1
        guard let status = reads.popFirst() ?? nil else { throw ACDeviceError.unreachable }
        return status
    }

    func write(_ change: ACChange, current: ACStatus) async throws {
        writes.append(change)
        if let writeError { throw writeError }
    }
}
