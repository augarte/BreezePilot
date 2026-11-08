import Foundation
import Observation

@MainActor @Observable
final class ACListViewModel {
    private(set) var summaries: [UUID: ACStatus] = [:]
    private(set) var loading = false
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
        if refreshID == id, !Task.isCancelled { summaries = results }
    }
}
