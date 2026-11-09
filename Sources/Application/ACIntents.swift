import AppIntents
import Foundation

struct AirConditionerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Air Conditioner"
    static let defaultQuery = AirConditionerQuery()
    static let unselected = AirConditionerEntity(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "None", roomName: nil
    )

    let id: UUID
    let name: String
    let roomName: String?

    var displayRepresentation: DisplayRepresentation {
        if id == Self.unselected.id { return DisplayRepresentation(title: "None") }
        return DisplayRepresentation(title: "\(name)", subtitle: roomName.map { "\($0)" })
    }

    init(_ item: WidgetAC) {
        self.init(id: item.unit.id, name: item.unit.name, roomName: item.roomName)
    }

    private init(id: UUID, name: String, roomName: String?) {
        self.id = id
        self.name = name
        self.roomName = roomName
    }
}

struct AirConditionerQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AirConditionerEntity] {
        let units = ACWidgetStore.catalog
        return identifiers.compactMap { id in
            units.first { $0.unit.id == id }.map(AirConditionerEntity.init)
        }
    }

    func suggestedEntities() async throws -> [AirConditionerEntity] {
        ACWidgetStore.catalog.map(AirConditionerEntity.init)
    }
}

struct SetACPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set AC Power"
    static let description = IntentDescription("Turn a saved air conditioner on or off.")

    @Parameter(title: "Air Conditioner") var unit: AirConditionerEntity
    @Parameter(title: "Power On") var isOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$unit) power to \(\.$isOn)")
    }

    init() {}

    init(unit: AirConditionerEntity, isOn: Bool) {
        self.unit = unit
        self.isOn = isOn
    }

    func perform() async throws -> some IntentResult {
        try await ACIntentCommand.run(for: unit.id) { _ in .power(isOn) }
        return .result()
    }
}

struct SetACTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Set AC Temperature"
    static let description = IntentDescription("Set a saved air conditioner’s target temperature in Celsius.")

    @Parameter(title: "Air Conditioner") var unit: AirConditionerEntity
    @Parameter(title: "Temperature (°C)") var celsius: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$unit) to \(\.$celsius) °C")
    }

    func perform() async throws -> some IntentResult {
        try await ACIntentCommand.run(for: unit.id) { device in
            let status = try await device.readStatus()
            guard let target = Int(exactly: celsius * 2), status.canAdjust,
                  status.permitsTarget(target), let mode = status.mode else {
                throw ACIntentCommand.Failure(message: "Choose a temperature supported by the AC’s current mode and settings.")
            }
            return .target(target, previous: status.target, mode: mode)
        }
        return .result()
    }
}

struct AdjustACWidgetTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust AC Widget Temperature"
    static let isDiscoverable = false

    @Parameter(title: "Air Conditioner") var unit: AirConditionerEntity
    @Parameter(title: "Target") var target: Int
    @Parameter(title: "Previous Target") var previous: Int
    @Parameter(title: "Mode") var mode: String

    init() {}

    init(unit: AirConditionerEntity, target: Int, previous: Int, mode: ClimateMode) {
        self.unit = unit
        self.target = target
        self.previous = previous
        self.mode = mode.rawValue
    }

    func perform() async throws -> some IntentResult {
        try await ACIntentCommand.run(for: unit.id) { _ in
            guard let climateMode = ClimateMode(rawValue: mode) else {
                throw ACIntentCommand.Failure(message: "The AC’s mode is unavailable.")
            }
            return .target(target, previous: previous, mode: climateMode)
        }
        return .result()
    }
}

struct SetACWidgetFanSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Set AC Widget Fan Speed"
    static let isDiscoverable = false

    @Parameter(title: "Air Conditioner") var unit: AirConditionerEntity
    @Parameter(title: "Fan Speed") var speed: String
    @Parameter(title: "Mode") var mode: String

    init() {}

    init(unit: AirConditionerEntity, speed: FanSpeed, mode: ClimateMode) {
        self.unit = unit
        self.speed = speed.rawValue
        self.mode = mode.rawValue
    }

    func perform() async throws -> some IntentResult {
        try await ACIntentCommand.run(for: unit.id) { _ in
            guard let fanSpeed = FanSpeed(rawValue: speed), let climateMode = ClimateMode(rawValue: mode) else {
                throw ACIntentCommand.Failure(message: "That fan speed is unavailable.")
            }
            return .fan(fanSpeed, mode: climateMode)
        }
        return .result()
    }
}

struct RefreshACWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Air Conditioners"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        // WidgetKit reloads the timeline after the action, so the provider reads each selected AC again.
        .result()
    }
}

private enum ACIntentCommand {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run(
        for id: UUID,
        change: (any ACDevice) async throws -> ACChange
    ) async throws {
        defer { ACWidgetStore.reload() }
        do {
            guard let unit = ACWidgetStore.catalog.first(where: { $0.unit.id == id })?.unit,
                  let address = LocalAddress(unit.address) else {
                throw Failure(message: "Choose an air conditioner saved in BreezePilot.")
            }
            let device = ACDevices.local.make(unit, address)
            let command = try await change(device)
            let result = try await ApplyACChange(device: device, unitID: id)(command)
            if let message = result.message { throw Failure(message: message) }
            ACWidgetStore.recordFailure(nil, for: id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ACWidgetStore.recordFailure(error.localizedDescription, for: id)
            throw error
        }
    }
}
