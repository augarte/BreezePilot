#if DEBUG
import Foundation

enum ACUITestFixture: String {
    case connected
    case unavailable
    case setups

    @MainActor
    func makeLibrary() -> ACLibrary {
        let suite = "local.breezepilot.ui-test-host"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let library = ACLibrary(defaults: defaults, fallbackAddress: nil)
        if self == .setups {
            library.save(SavedAC(name: "Living Room AC", address: "10.20.30.40"))
            let bedroom = library.rooms.first { $0.name == "Bedroom" }
            library.save(SavedAC(name: "Bedroom AC", address: "10.20.30.41", roomID: bedroom?.id))
        } else {
            library.save(SavedAC(name: "Demo AC", address: "192.168.1.10"))
        }
        return library
    }

    func makeDevices() -> ACDevices {
        if self == .setups {
            let bedroom = SimulatedAC(isReachable: true, target: 51)
            let living = SimulatedAC(isReachable: false)
            return ACDevices(make: { unit, _ in unit.name == "Bedroom AC" ? bedroom : living },
                             xiaomiSetup: DisabledXiaomiSetup())
        }
        let device = SimulatedAC(isReachable: self == .connected)
        return ACDevices(make: { _, _ in device }, xiaomiSetup: DisabledXiaomiSetup())
    }
}

private actor SimulatedAC: ACDevice {
    let isReachable: Bool
    private var isOn = true
    private var mode = ClimateMode.cool
    private var target: Int
    private var speed = FanSpeed.two

    init(isReachable: Bool, target: Int = 48) {
        self.isReachable = isReachable
        self.target = target
    }

    func readStatus() throws -> ACStatus {
        guard isReachable else { throw ACDeviceError.unreachable }
        return ACStatus(isOn: isOn, mode: mode, availableModes: ClimateMode.selectable,
                        room: RoomConditions(temperature: 52, humidity: 55),
                        target: target, limits: 36...60,
                        fan: ACFan(selected: speed, available: FanSpeed.daikin),
                        features: ACFeatures(boost: nil, econo: nil, streamer: nil))
    }

    func write(_ change: ACChange, current: ACStatus) throws {
        guard isReachable else { throw ACDeviceError.unreachable }
        switch change {
        case let .power(value): isOn = value
        case let .mode(value): mode = value
        case let .target(value, _, _): target = value
        case let .fan(value, _): speed = value
        case .special, .streamer: throw ACDeviceError.unexpectedResponse
        }
    }
}

private struct DisabledXiaomiSetup: XiaomiSetup {
    func check(address: LocalAddress, token: XiaomiToken) async throws -> XiaomiProfile {
        throw ACDeviceError.unreachable
    }

    func save(_ token: XiaomiToken, for id: UUID) throws {
        throw ACDeviceError.unreachable
    }

    func removeToken(for id: UUID) throws {}
}
#endif
