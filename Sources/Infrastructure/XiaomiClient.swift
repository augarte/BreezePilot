import Foundation

struct XiaomiClient: ACDevice {
    let address: LocalAddress
    let profile: XiaomiProfile
    let credentials: Credentials

    enum Credentials: Sendable {
        case stored(UUID)
        case setup(XiaomiToken)
    }

    static func checkConnection(address: LocalAddress, token: XiaomiToken) async throws -> XiaomiProfile {
        let requests = XiaomiRequestProvider(address: address, token: token)
        let (id, info): (UInt64, DeviceInfo) = try await requests.request("miIO.info", parameters: { _ in [String]() })
        let profile = try await XiaomiModelCatalog().profile(for: info.model, deviceID: id)
        _ = try await XiaomiClient(address: address, profile: profile, credentials: .setup(token)).readStatus()
        return profile
    }

    func readStatus() async throws -> ACStatus {
        let properties = [
            profile.power, profile.mode, profile.setpoint?.property, profile.fan,
            profile.roomTemperature, profile.roomHumidity, profile.eco
        ].compactMap { $0 }
        let provider = try requestProvider()
        let (_, replies): (UInt64, [PropertyReply]) = try await provider.request(
            "get_properties",
            parameters: { id in properties.map { PropertyRequest(id: id, property: $0) } },
            deviceID: profile.deviceID
        )

        func value(_ property: XiaomiProfile.Property?) -> Value? {
            guard let property else { return nil }
            return replies.first { $0.siid == property.service && $0.piid == property.property && $0.code == 0 }?.value
        }
        guard case let .boolean(isOn) = value(profile.power) else { throw XiaomiError.incompatible }

        let modeValue = value(profile.mode)?.integer
        let mode = ClimateMode.allCases.first { profile.modes[$0].map { $0 == modeValue } ?? false }
        let fanValue = value(profile.fan)?.integer
        let selectedFan = FanSpeed.allCases.first { profile.speeds[$0].map { $0 == fanValue } ?? false }
        let target = value(profile.setpoint?.property)?.number.flatMap { Int(exactly: $0 * 2) }
            .flatMap { (0...100).contains($0) ? $0 : nil }
        let temperature = value(profile.roomTemperature)?.number.flatMap { Int(exactly: $0.rounded()) }
            .flatMap { (-20...70).contains($0) ? $0 : nil }
        let humidity = value(profile.roomHumidity)?.number.flatMap { Int(exactly: $0.rounded()) }
            .flatMap { (0...100).contains($0) ? $0 : nil }
        let fan = fanValue.map { _ in
            ACFan(selected: selectedFan, available: profile.fan?.writable == true
                  ? FanSpeed.allCases.filter { profile.speeds[$0] != nil } : [])
        }
        let eco: Bool?
        if case let .boolean(enabled) = value(profile.eco) { eco = enabled } else { eco = nil }

        return ACStatus(
            isOn: isOn,
            mode: mode,
            availableModes: modeValue != nil && profile.mode?.writable == true
                ? ClimateMode.allCases.filter { profile.modes[$0] != nil } : [],
            room: RoomConditions(temperature: temperature, humidity: humidity),
            target: target,
            limits: profile.setpoint?.property.writable == true ? profile.setpoint?.limits : nil,
            fan: fan,
            features: ACFeatures(boost: nil, econo: eco, streamer: nil),
            targetStep: profile.setpoint?.step ?? 1,
            targetModes: [.cool, .heat],
            powerWritable: profile.power.writable,
            usesDeviceOptions: true
        )
    }

    func write(_ change: ACChange, current: ACStatus) async throws {
        switch change {
        case let .power(isOn):
            try await set(profile.power, to: .boolean(isOn))
        case let .target(target, _, mode):
            guard current.mode == mode, current.canAdjust, current.permitsTarget(target) else {
                throw XiaomiError.incompatible
            }
            try await set(profile.setpoint?.property, to: .numeric(Double(target) / 2))
        case let .mode(mode):
            try await set(profile.mode, to: profile.modes[mode].map { .numeric(Double($0)) })
        case let .fan(speed, _):
            try await set(profile.fan, to: profile.speeds[speed].map { .numeric(Double($0)) })
        case let .special(operation) where operation == .econo || operation == .off:
            try await set(profile.eco, to: .boolean(operation == .econo))
        case .special, .streamer:
            throw XiaomiError.incompatible
        }
    }

    private func set(_ property: XiaomiProfile.Property?, to value: Value?) async throws {
        guard let property, property.writable, let value else { throw XiaomiError.incompatible }
        let provider = try requestProvider()
        let (_, replies): (UInt64, [PropertyReply]) = try await provider.request(
            "set_properties",
            parameters: { id in [PropertyRequest(id: id, property: property, value: value)] },
            deviceID: profile.deviceID
        )
        guard replies.contains(where: { $0.siid == property.service && $0.piid == property.property && $0.code == 0 }) else {
            throw ACDeviceError.unconfirmed
        }
    }

    private func requestProvider() throws -> XiaomiRequestProvider {
        let token: XiaomiToken
        switch credentials {
        case let .stored(id): token = try XiaomiTokenStore.read(for: id)
        case let .setup(value): token = value
        }
        return XiaomiRequestProvider(address: address, token: token)
    }

    private struct DeviceInfo: Decodable {
        let model: String
    }

    private struct PropertyRequest: Encodable, Sendable {
        let did: String
        let siid: Int
        let piid: Int
        let value: Value?

        init(id: UInt64, property: XiaomiProfile.Property, value: Value? = nil) {
            did = String(id)
            siid = property.service
            piid = property.property
            self.value = value
        }
    }

    private struct PropertyReply: Decodable, Sendable {
        let siid: Int
        let piid: Int
        let code: Int
        let value: Value?
    }

    private enum Value: Codable, Sendable {
        case boolean(Bool)
        case numeric(Double)
        case other

        var number: Double? {
            if case let .numeric(number) = self { number } else { nil }
        }

        var integer: Int? { number.flatMap { Int(exactly: $0) } }

        init(from decoder: Decoder) throws {
            let box = try decoder.singleValueContainer()
            if let value = try? box.decode(Bool.self) {
                self = .boolean(value)
            } else if let value = try? box.decode(Double.self) {
                self = .numeric(value)
            } else {
                self = .other
            }
        }

        func encode(to encoder: Encoder) throws {
            var box = encoder.singleValueContainer()
            switch self {
            case let .boolean(value): try box.encode(value)
            case let .numeric(value): try box.encode(value)
            case .other: try box.encodeNil()
            }
        }
    }
}
