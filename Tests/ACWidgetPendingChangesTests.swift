import Foundation
import Testing
@testable import BreezePilot

struct ACWidgetPendingChangesTests {
    private func makeStore() throws -> (ACWidgetPendingChanges, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ACWidgetPendingChanges(directory: directory, quietPeriod: 0, powerQuietPeriod: 0), directory)
    }

    @Test func tapsAreVisibleImmediatelyAndClearOnceApplied() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unit = UUID()
        let device = SettingsDevice(isOn: false)

        store.enqueue(.power(true), for: unit)
        store.enqueue(.fan(.init(speed: .three, mode: .cool)), for: unit)
        #expect(store.power(for: unit) == true)
        #expect(store.fan(for: unit) == .three)
        #expect(await device.writes.isEmpty)

        let status = await store.applyPending(for: unit, device: device, waitForReadback: {})

        #expect(status != nil)
        #expect(await device.writes == ["power on", "fan 3"])
        #expect(!store.hasPending(for: unit))
    }

    @Test func aRunOfFanTapsWritesOnlyTheFinalSpeed() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unit = UUID()
        let device = SettingsDevice()

        for speed in [FanSpeed.two, .three, .four, .five] {
            store.enqueue(.fan(.init(speed: speed, mode: .cool)), for: unit)
        }
        #expect(store.fan(for: unit) == .five)

        _ = await store.applyPending(for: unit, device: device, waitForReadback: {})

        #expect(await device.writes == ["fan 5"])
    }

    @Test func aRefusedChangeRollsBackAndRecordsNothingPending() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unit = UUID()
        let device = SettingsDevice(refusing: true)

        store.enqueue(.power(false), for: unit)
        _ = await store.applyPending(for: unit, device: device, waitForReadback: {})

        #expect(!store.hasPending(for: unit))
        #expect(store.power(for: unit) == nil)
    }

    @Test func pendingChangesAreKeptPerAC() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID(), second = UUID()

        store.enqueue(.power(false), for: first)

        #expect(store.power(for: first) == false)
        #expect(store.power(for: second) == nil)
    }

    @Test func refreshStateStartsAndEnds() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(!store.isRefreshing)
        store.beginRefresh()
        #expect(store.isRefreshing)
        store.endRefresh()
        #expect(!store.isRefreshing)
    }

    @Test func everySceneIconHasAMeaningfulUniqueLabelAndSymbol() {
        let labels = ACSetupIcon.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(Set(ACSetupIcon.allCases.map(\.symbol)).count == labels.count)
        #expect(ACSetupIcon.moon.label == "Sleep")
        #expect(ACSetupIcon.allCases.count >= 16)
    }
}

private actor SettingsDevice: ACDevice {
    private var isOn: Bool
    private var fan: FanSpeed = .one
    private let refusing: Bool
    private(set) var writes: [String] = []

    init(isOn: Bool = true, refusing: Bool = false) {
        self.isOn = isOn
        self.refusing = refusing
    }

    func readStatus() throws -> ACStatus {
        ACStatus(isOn: isOn, mode: .cool, availableModes: [.cool],
                 room: RoomConditions(temperature: nil, humidity: nil), target: 50, limits: 36...60,
                 fan: ACFan(selected: fan, available: FanSpeed.daikin),
                 features: ACFeatures(boost: nil, econo: nil, streamer: nil))
    }

    func write(_ change: ACChange, current: ACStatus) throws {
        if refusing { return }
        switch change {
        case let .power(on): isOn = on; writes.append("power \(on ? "on" : "off")")
        case let .fan(speed, _): fan = speed; writes.append("fan \(speed.rawValue)")
        default: throw ACDeviceError.unexpectedResponse
        }
    }
}
