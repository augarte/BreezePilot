import Testing
@testable import BreezePilot

struct ACStatusTests {
    @Test func adjustsFromTheLatestDraftInHalfDegrees() {
        let status = sampleStatus(target: 54)
        #expect(status.adjusted(by: -1) == 53)
        #expect(status.adjusted(by: -1, from: 53) == 52)
    }

    @Test func respectsADevicesWholeDegreeStep() {
        let status = sampleStatus(target: 54, step: 2)
        #expect(status.adjusted(by: -1) == 52)
        #expect(!status.permitsTarget(53))
    }

    @Test func stopsAtTheDevicesLimits() {
        let status = sampleStatus(target: 36)
        #expect(status.adjusted(by: -1) == nil)
        #expect(status.adjusted(by: 1, from: 64) == nil)
        #expect(status.permitsTarget(36))
        #expect(status.permitsTarget(64))
    }

    @Test func temperatureAdjustmentRequiresPowerAndASupportedMode() {
        #expect(sampleStatus(isOn: false).adjusted(by: 1) == nil)
        #expect(sampleStatus(mode: .fan).adjusted(by: 1) == nil)
        #expect(sampleStatus(target: nil).adjusted(by: 1) == nil)
    }

    @Test func confirmsOnlyMutuallyExclusiveSpecialOperations() {
        let boost = ACFeatures(boost: true, econo: false, streamer: nil)
        #expect(boost.confirms(.boost))
        #expect(!boost.confirms(.econo))
        #expect(!boost.confirms(.off))
        #expect(!ACFeatures(boost: true, econo: true, streamer: nil).confirms(.boost))
        #expect(!ACFeatures(boost: nil, econo: nil, streamer: nil).confirms(.off))
    }

    @Test func expectingShowsTappedChangesAndKeepsTheRest() {
        let off = ACStatus(
            isOn: false, mode: .cool, availableModes: [.cool],
            room: RoomConditions(temperature: 26, humidity: 55), target: 54, limits: 36...64,
            fan: ACFan(selected: .two, available: [.one, .two, .three]),
            features: ACFeatures(boost: nil, econo: nil, streamer: nil)
        )
        // The temperature buttons only work on an AC that is on, so a power tap has to count straight away.
        #expect(off.adjusted(by: 1) == nil)
        let turnedOn = off.expecting(power: true)
        #expect(turnedOn.isOn)
        #expect(turnedOn.adjusted(by: 1) == 55)
        #expect(turnedOn.target == 54)
        #expect(turnedOn.fan?.selected == .two)
        #expect(turnedOn.room.temperature == 26)

        let changed = off.expecting(power: true, target: 52, fan: .three)
        #expect(changed.isOn && changed.target == 52 && changed.fan?.selected == .three)
        #expect(changed.fan?.available == [.one, .two, .three])
        #expect(off.expecting().isOn == false && off.expecting().target == 54)
    }
}

func sampleStatus(
    target: Int? = 54,
    mode: ClimateMode = .cool,
    isOn: Bool = true,
    step: Int = 1
) -> ACStatus {
    ACStatus(
        isOn: isOn,
        mode: mode,
        availableModes: [.cool, .fan, .dry],
        room: RoomConditions(temperature: nil, humidity: nil),
        target: target,
        limits: 36...64,
        fan: nil,
        features: ACFeatures(boost: nil, econo: nil, streamer: nil),
        targetStep: step
    )
}
