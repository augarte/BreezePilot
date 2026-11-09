import Foundation

protocol ACDevice: Sendable {
    func readStatus() async throws -> ACStatus
    func write(_ change: ACChange, current: ACStatus) async throws
}

typealias MakeACDevice = @Sendable (SavedAC, LocalAddress) -> any ACDevice

struct ACDevices: Sendable {
    let make: MakeACDevice
    let xiaomiSetup: any XiaomiSetup

    static let local = ACDevices(
        make: { unit, address in
            if let profile = unit.xiaomi {
                return XiaomiClient(address: address, profile: profile, credentials: .stored(unit.id))
            }
            return DaikinClient(address: address)
        },
        xiaomiSetup: XiaomiLocalSetup()
    )
}

enum ACChange: Sendable {
    case target(Int, previous: Int?, mode: ClimateMode)
    case power(Bool)
    case mode(ClimateMode)
    case fan(FanSpeed, mode: ClimateMode)
    case special(SpecialOperation)
    case streamer(Bool)
}

enum ACDeviceError: LocalizedError {
    case unreachable
    case unexpectedResponse
    case unconfirmed
    case commandInProgress

    var errorDescription: String? {
        switch self {
        case .unreachable: "Connect to the same Wi-Fi network as your AC."
        case .unexpectedResponse: "This address didn’t return a compatible Daikin status."
        case .commandInProgress: "Another AC change is in progress. Try again in a moment."
        case .unconfirmed: "The AC’s response didn’t confirm the change. Refresh before trying again."
        }
    }
}
