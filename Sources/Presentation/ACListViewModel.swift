import Foundation
import Observation

@MainActor @Observable
final class ACListViewModel {
    private(set) var summaries: [UUID: ACStatus] = [:]
    private(set) var loading = false
    /// Units with a power change in flight.
    private(set) var busy: Set<UUID> = []
    private let makeDevice: MakeACDevice
    @ObservationIgnored private var refreshID = UUID()

    init(makeDevice: @escaping MakeACDevice) {
        self.makeDevice = makeDevice
    }

    func refresh(_ units: [SavedAC]) async {
        let id = UUID()
        let makeDevice = self.makeDevice
        refreshID = id
        loading = true
        defer { if refreshID == id { loading = false } }

        let results = await withTaskGroup(of: (UUID, ACStatus?).self) { group in
            for unit in units {
                guard let address = LocalAddress(unit.address) else { continue }
                group.addTask {
                    let status = try? await makeDevice(unit, address).readStatus()
                    return (unit.id, status)
                }
            }
            var results: [UUID: ACStatus] = [:]
            for await (id, status) in group { results[id] = status }
            return results
        }
        guard refreshID == id, !Task.isCancelled else { return }
        // A read taken while a power change was in flight may predate it. Keep what the change reports.
        var merged = results
        for id in busy { merged[id] = summaries[id] }
        summaries = merged
    }

    func togglePower(_ unit: SavedAC) async {
        guard !busy.contains(unit.id), let status = summaries[unit.id], status.powerWritable,
              let address = LocalAddress(unit.address) else { return }
        busy.insert(unit.id)
        defer { busy.remove(unit.id) }

        let device = makeDevice(unit, address)
        do {
            let result = try await ApplyACChange(device: device, unitID: unit.id)(.power(!status.isOn))
            summaries[unit.id] = result.status
            ACWidgetStore.recordFailure(nil, for: unit.id)
            ACWidgetStore.reload()
        } catch {
            // Show what the AC reports now instead of guessing whether the change landed.
            summaries[unit.id] = try? await device.readStatus()
        }
    }
}
