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
        ACIntentCommand.enqueue(for: unit.id, kind: .power(isOn))
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
    @Parameter(title: "Minimum Target") var minimum: Int?
    @Parameter(title: "Maximum Target") var maximum: Int?
    @Parameter(title: "Reading Date") var observedAt: Date?
    @Parameter(title: "Confirmed Target") var confirmed: Int?

    init() {}

    init(unit: AirConditionerEntity, target: Int, previous: Int, mode: ClimateMode,
         limits: ClosedRange<Int>, observedAt: Date, confirmed: Int) {
        self.unit = unit
        self.target = target
        self.previous = previous
        self.mode = mode.rawValue
        self.minimum = limits.lowerBound
        self.maximum = limits.upperBound
        self.observedAt = observedAt
        self.confirmed = confirmed
    }

    func perform() async throws -> some IntentResult {
        do {
            guard let climateMode = ClimateMode(rawValue: mode) else {
                throw ACIntentCommand.Failure(message: "The AC’s mode is unavailable.")
            }
            // Already rendered widgets may still carry the previous version of this intent.
            guard let minimum, let maximum, minimum <= maximum else {
                try await ACIntentCommand.run(for: unit.id) { _ in
                    .target(target, previous: previous, mode: climateMode)
                }
                return .result()
            }
            guard let directory = ACWidgetStore.container else {
                throw ACIntentCommand.Failure(message: "BreezePilot couldn’t share this temperature change with the widget.")
            }
            guard let saved = ACWidgetStore.catalog.first(where: { $0.unit.id == unit.id })?.unit,
                  let address = LocalAddress(saved.address) else {
                throw ACIntentCommand.Failure(message: "Choose an air conditioner saved in BreezePilot.")
            }
            let edits = ACWidgetTemperatureEdits(directory: directory)
            try edits.enqueue(
                for: unit.id, previous: previous, target: target, mode: climateMode,
                limits: minimum...maximum, observedAt: observedAt ?? .distantPast,
                confirmedTarget: confirmed
            )
            ACWidgetTemperatureActivity.schedule(unit: saved, address: address, edits: edits)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ACWidgetStore.recordFailure(error.localizedDescription, for: unit.id)
            ACWidgetStore.reload()
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
        guard let fanSpeed = FanSpeed(rawValue: speed), let climateMode = ClimateMode(rawValue: mode) else {
            ACWidgetStore.recordFailure("That fan speed is unavailable.", for: unit.id)
            ACWidgetStore.reload()
            return .result()
        }
        ACIntentCommand.enqueue(for: unit.id, kind: .fan(.init(speed: fanSpeed, mode: climateMode)))
        return .result()
    }
}

struct RefreshACWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Air Conditioners"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        // Mark the widget as refreshing and return, so it redraws now. A background activity reads the
        // ACs, clears the marker and reloads the widget when it is done.
        ACWidgetDiagnostics.log("refresh intent refreshing=\(ACWidgetStore.pending?.isRefreshing ?? false)")
        guard let pending = ACWidgetStore.pending, !pending.isRefreshing else { return .result() }
        pending.beginRefresh()
        ACWidgetPendingActivity.refresh(catalog: ACWidgetStore.catalog, pending: pending)
        return .result()
    }
}

private enum ACIntentCommand {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Queues a widget tap and returns at once, so the widget redraws with the new value before the AC answers.
    static func enqueue(for id: UUID, kind: ACWidgetPendingChanges.Kind) {
        ACWidgetDiagnostics.log("enqueue \(kind) container=\(ACWidgetStore.container != nil) catalog=\(ACWidgetStore.catalog.count)")
        guard let pending = ACWidgetStore.pending,
              let unit = ACWidgetStore.catalog.first(where: { $0.unit.id == id })?.unit,
              let address = LocalAddress(unit.address) else {
            ACWidgetDiagnostics.log("enqueue guard failed")
            ACWidgetStore.recordFailure("Choose an air conditioner saved in BreezePilot.", for: id)
            ACWidgetStore.reload()
            return
        }
        ACWidgetStore.recordFailure(nil, for: id)
        pending.enqueue(kind, for: id)
        ACWidgetStore.reload()
        ACWidgetPendingActivity.schedule(unit: unit, address: address, pending: pending)
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
            ACWidgetStore.cacheStatus(result.status, for: id)
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
