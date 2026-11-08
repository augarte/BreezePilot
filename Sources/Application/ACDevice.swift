import Foundation

protocol ACDevice: Sendable {
    func readStatus() async throws -> ACStatus
    func write(_ change: ACChange, current: ACStatus) async throws
}

typealias MakeACDevice = @Sendable (SavedAC, LocalAddress) -> any ACDevice

struct ACDevices: Sendable {
    let make: MakeACDevice
    let xiaomiSetup: any XiaomiSetup
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

    var errorDescription: String? {
        switch self {
        case .unreachable: "Can’t reach the AC. Check your home Wi‑Fi, the saved address, and Local Network access."
        case .unexpectedResponse: "This address didn’t return a compatible Daikin status."
        case .unconfirmed: "The AC’s response didn’t confirm the change. Refresh before trying again."
        }
    }
}
