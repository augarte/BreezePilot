import Foundation
import OSLog
import WidgetKit

enum ACSetupStore {
    static let kind = "BreezePilotSetups"
    static let homeURL = URL(string: "breezepilot://setups")!
    private static let logger = Logger(subsystem: "local.daikin.directcontrol", category: "Setups")

    static var catalog: [ACSetup] {
        read("setups.json") ?? []
    }

    static func detailsURL(for id: UUID) -> URL {
        homeURL.appendingPathComponent(id.uuidString)
    }

    static func publish(_ setups: [ACSetup]) {
        write(setups, to: "setups.json")
        reload()
    }

    static func lastResult(for setup: ACSetup) -> ACSetupRunResult? {
        let result: ACSetupRunResult? = read(resultFile(setup.id))
        guard result?.revision == setup.revision else { return nil }
        return result
    }

    static func record(_ result: ACSetupRunResult) {
        write(result, to: resultFile(result.setupID))
        reload()
    }

    static func removeResult(for id: UUID) {
        guard let url = ACWidgetStore.container?.appendingPathComponent(resultFile(id)) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func reload() {
        guard ACWidgetStore.container != nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func resultFile(_ id: UUID) -> String { "setup-\(id.uuidString).result.json" }

    private static func read<Value: Decodable>(_ filename: String) -> Value? {
        guard let url = ACWidgetStore.container?.appendingPathComponent(filename),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func write<Value: Encodable>(_ value: Value, to filename: String) {
        guard let url = ACWidgetStore.container?.appendingPathComponent(filename) else { return }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            logger.error("Could not write setup data: \(error.localizedDescription, privacy: .private)")
        }
    }
}
