import Foundation
import Testing
@testable import BreezePilot

struct ACSetupTests {
    @Test func appliesPowerModeTemperatureAndFanInOrderAndSkipsSatisfiedWrites() async throws {
        let unit = SavedAC(name: "Bedroom", address: "10.20.30.41")
        let device = SetupDevice(on: false, mode: .fan)
        let setup = ACSetup(name: "Sleep", targets: [
            ACSetupTarget(id: unit.id, unitName: unit.name, power: true, mode: .cool, temperature: 52, fan: .three)
        ])
        let run = RunACSetup(makeDevice: { _, _ in device }, waitForReadback: {})

        let result = try await run(setup, units: [unit])

        #expect(result.allApplied)
        #expect(await device.writes == ["on", "Cool", "52", "Fan 3"])
        #expect(try await run(setup, units: [unit]).allApplied)
        #expect(await device.writes == ["on", "Cool", "52", "Fan 3"])
    }

    @Test func retriesOnlyFailedACsAndKeepsResultsInSetupOrder() async throws {
        let living = SavedAC(name: "Living Room", address: "10.20.30.40")
        let bedroom = SavedAC(name: "Bedroom", address: "10.20.30.41")
        let unavailable = SetupDevice(reachable: false)
        let working = SetupDevice()
        let setup = ACSetup(name: "Sleep", targets: [
            ACSetupTarget(id: living.id, unitName: living.name, power: false),
            ACSetupTarget(id: bedroom.id, unitName: bedroom.name, temperature: 52)
        ])
        let run = RunACSetup(makeDevice: { unit, _ in unit.id == living.id ? unavailable : working },
                             waitForReadback: {})

        let first = try await run(setup, units: [living, bedroom])
        #expect(first.units.map(\.id) == [living.id, bedroom.id])
        #expect(first.units.map(\.outcome) == [.failed, .applied])
        let bedroomReads = await working.reads

        await unavailable.reconnect()
        let retry = try await run(setup, units: [living, bedroom], retrying: first)

        #expect(retry.allApplied)
        #expect(await unavailable.writes == ["off"])
        #expect(await working.reads == bedroomReads)
    }

    @Test func reportsConfirmedChangesWhenALaterStepFails() async throws {
        let unit = SavedAC(name: "Bedroom", address: "10.20.30.41")
        let device = SetupDevice(on: false)
        let setup = ACSetup(name: "Warm Up", targets: [
            ACSetupTarget(id: unit.id, unitName: unit.name, power: true, mode: .heat, temperature: 52)
        ])
        let run = RunACSetup(makeDevice: { _, _ in device }, waitForReadback: {})

        let result = try #require(try await run(setup, units: [unit]).units.first)

        #expect(result.outcome == .failed)
        #expect(result.confirmed == ["On"])
        #expect(result.message != nil)
        #expect(await device.writes == ["on"])
    }

    @Test func turningOffIgnoresOtherFieldsAndMissingACsAreReported() async throws {
        let unit = SavedAC(name: "Living Room", address: "10.20.30.40")
        let missing = UUID()
        let device = SetupDevice()
        let setup = ACSetup(name: "Leave", targets: [
            ACSetupTarget(id: unit.id, unitName: unit.name, power: false, mode: .cool, temperature: 52, fan: .three),
            ACSetupTarget(id: missing, unitName: "Removed AC", power: false)
        ])
        let run = RunACSetup(makeDevice: { _, _ in device }, waitForReadback: {})

        let result = try await run(setup, units: [unit])

        #expect(result.units.map(\.outcome) == [.applied, .missing])
        #expect(result.units.last?.name == "Removed AC")
        #expect(result.units.last?.canRetry == false)
        #expect(await device.writes == ["off"])
    }

    @MainActor @Test func savedSetupSurvivesReloadAndUsesTheACIdentity() throws {
        let suite = "ac-setups-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = ACLibrary(defaults: defaults, fallbackAddress: nil)
        var unit = SavedAC(name: "Living Room", address: "10.20.30.40")
        library.save(unit)
        let draft = ACSetup(name: " Leave ", targets: [
            ACSetupTarget(id: unit.id, unitName: unit.name, power: false, temperature: 52)
        ])

        #expect(library.saveSetup(draft))
        unit.name = "Lounge"
        library.save(unit)
        let reloaded = ACLibrary(defaults: defaults, fallbackAddress: nil)
        let setup = try #require(reloaded.setups.first)

        #expect(setup.id == draft.id)
        #expect(setup.name == "Leave")
        #expect(setup.targets.first?.id == unit.id)
        #expect(setup.targets.first?.temperature == nil)
        #expect(setup.summary(names: [unit.id: unit.name]) == "Lounge: Off")
        reloaded.removeSetup(setup.id)
        #expect(ACLibrary(defaults: defaults, fallbackAddress: nil).setups.isEmpty)
    }
}

private actor SetupDevice: ACDevice {
    private var reachable: Bool
    private var on: Bool
    private var mode: ClimateMode
    private var temperature = 48
    private var fan: FanSpeed = .two
    private(set) var writes: [String] = []
    private(set) var reads = 0

    init(on: Bool = true, mode: ClimateMode = .cool, reachable: Bool = true) {
        self.on = on
        self.mode = mode
        self.reachable = reachable
    }

    func reconnect() { reachable = true }

    func readStatus() throws -> ACStatus {
        reads += 1
        guard reachable else { throw ACDeviceError.unreachable }
        return ACStatus(isOn: on, mode: mode, availableModes: [.cool, .fan],
                        room: RoomConditions(temperature: nil, humidity: nil),
                        target: temperature, limits: 36...60,
                        fan: ACFan(selected: fan, available: FanSpeed.daikin),
                        features: ACFeatures(boost: nil, econo: nil, streamer: nil))
    }

    func write(_ change: ACChange, current: ACStatus) throws {
        switch change {
        case let .power(value): on = value; writes.append(value ? "on" : "off")
        case let .mode(value): mode = value; writes.append(value.label)
        case let .target(value, _, _): temperature = value; writes.append(String(value))
        case let .fan(value, _): fan = value; writes.append("Fan \(value.label)")
        case .special, .streamer: throw ACDeviceError.unexpectedResponse
        }
    }
}
