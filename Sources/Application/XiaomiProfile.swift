import Foundation

protocol XiaomiSetup: Sendable {
    func check(address: LocalAddress, token: XiaomiToken) async throws -> XiaomiProfile
    func save(_ token: XiaomiToken, for id: UUID) throws
    func removeToken(for id: UUID) throws
}

struct XiaomiToken: Sendable {
    let bytes: Data

    init?(_ input: String) {
        let characters = Array(input.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard characters.count == 32 else { return nil }
        var bytes = Data()
        for index in stride(from: 0, to: characters.count, by: 2) {
            let pair = characters[index...index + 1]
            guard pair.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  let byte = UInt8(String(decoding: pair, as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.bytes = bytes
    }

    init?(bytes: Data) {
        guard bytes.count == 16 else { return nil }
        self.bytes = bytes
    }
}

struct XiaomiProfile: Codable, Hashable, Sendable {
    struct Property: Codable, Hashable, Sendable {
        let service: Int
        let property: Int
        let writable: Bool
    }

    struct Setpoint: Codable, Hashable, Sendable {
        let property: Property
        let limits: ClosedRange<Int>?
        let step: Int
    }

    let model: String
    let deviceID: UInt64
    let power: Property
    let mode: Property?
    let modes: [ClimateMode: Int]
    let setpoint: Setpoint?
    let fan: Property?
    let speeds: [FanSpeed: Int]
    let roomTemperature: Property?
    let roomHumidity: Property?
    let eco: Property?
}
