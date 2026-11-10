import Foundation

struct RunACSetup: Sendable {
    let makeDevice: MakeACDevice
    var waitForReadback: @Sendable () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(500))
    }

    func callAsFunction(_ setup: ACSetup, units: [SavedAC],
                        retrying previous: ACSetupRunResult? = nil) async throws -> ACSetupRunResult {
        guard setup.canSave else { throw Failure(message: "Edit this scene and choose at least one change for each AC.") }
        return try await ACCommandLock.withLock("setup-\(setup.id.uuidString)") {
            let previous = previous.flatMap {
                $0.setupID == setup.id && $0.revision == setup.revision ? $0 : nil
            }
            var results = [UUID: ACSetupRunResult.UnitResult]()
            let targets: [ACSetupTarget]
            if let previous {
                for result in previous.units { results[result.id] = result }
                let retryIDs = Set(previous.units.filter(\.canRetry).map(\.id))
                targets = setup.targets.filter { retryIDs.contains($0.id) }
            } else {
                targets = setup.targets
            }

            let parallelLimit = 3
            for start in stride(from: 0, to: targets.count, by: parallelLimit) {
                let batch = targets[start..<min(start + parallelLimit, targets.count)]
                await withTaskGroup(of: ACSetupRunResult.UnitResult.self) { group in
                    for target in batch {
                        let unit = units.first { $0.id == target.id }
                        group.addTask { await run(target, unit: unit) }
                    }
                    for await result in group { results[result.id] = result }
                }
            }
            let result = ACSetupRunResult(id: UUID(), setupID: setup.id, revision: setup.revision, date: .now,
                                          units: setup.targets.compactMap { results[$0.id] })
            ACSetupStore.record(result)
            ACWidgetStore.reload()
            return result
        }
    }

    private func run(_ target: ACSetupTarget, unit: SavedAC?) async -> ACSetupRunResult.UnitResult {
        guard let unit, let address = LocalAddress(unit.address) else {
            return .init(id: target.id, name: unit?.name ?? target.unitName, outcome: .missing,
                         confirmed: [], message: "This AC is no longer available in the library. Edit the scene to replace it.")
        }
        let device = makeDevice(unit, address)
        var confirmed: [String] = []
        do {
            try await ACCommandLock.withLock(unit.id.uuidString) {
                // The outer lock covers the complete sequence. Each write still checks fresh status and verifies readback.
                let apply = ApplyACChange(device: device, waitForReadback: waitForReadback)
                var latest: ACStatus?

                func set(_ change: ACChange, label: String) async throws {
                    let result = try await apply(change)
                    if let message = result.message { throw Failure(message: message) }
                    guard let status = result.status else { throw ACDeviceError.unconfirmed }
                    latest = status
                    confirmed.append(label)
                }

                func currentStatus() async throws -> ACStatus {
                    if let latest { return latest }
                    return try await device.readStatus()
                }

                if let power = target.power {
                    try await set(.power(power), label: power ? "On" : "Off")
                }
                guard target.power != false else { return }
                if let mode = target.mode {
                    try await set(.mode(mode), label: mode.label)
                }
                if let temperature = target.temperature {
                    let current = try await currentStatus()
                    guard let mode = current.mode else { throw Failure(message: "The AC’s current mode is unavailable.") }
                    try await set(.target(temperature, previous: current.target, mode: mode),
                                  label: ACStatus.degrees(temperature) + "°C")
                }
                if let fan = target.fan {
                    let current = try await currentStatus()
                    guard let mode = current.mode else { throw Failure(message: "The AC’s current mode is unavailable.") }
                    try await set(.fan(fan, mode: mode), label: "Fan \(fan.label)")
                }
            }
            return .init(id: target.id, name: unit.name, outcome: .applied, confirmed: confirmed)
        } catch {
            return .init(id: target.id, name: unit.name, outcome: .failed, confirmed: confirmed,
                         message: error is CancellationError ? "This run was interrupted." : error.localizedDescription)
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
