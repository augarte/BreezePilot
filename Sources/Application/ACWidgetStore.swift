import Foundation
import OSLog
import WidgetKit

struct WidgetAC: Codable, Hashable, Sendable {
    let unit: SavedAC
    let roomName: String?
}

enum ACWidgetStore {
    static let group = Bundle.main.object(forInfoDictionaryKey: "BreezePilotAppGroup") as? String
        ?? "group.local.daikin.directcontrol"
    static let kind = "BreezePilotAirConditioners"
    static let homeURL = URL(string: "breezepilot://air-conditioners")!
    private static let logger = Logger(subsystem: "local.daikin.directcontrol", category: "WidgetCatalog")
    private static let isTesting: Bool = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["BREEZEPILOT_UNIT_TESTING"] == "1"
        #else
        return false
        #endif
    }()

    static var container: URL? {
        guard !isTesting else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func controlURL(for id: UUID) -> URL {
        homeURL.appendingPathComponent(id.uuidString)
    }

    static var catalog: [WidgetAC] {
        guard let url = container?.appendingPathComponent("units.json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetAC].self, from: data)) ?? []
    }

    static func publish(_ units: [WidgetAC]) {
        guard !isTesting else { return }
        guard let url = container?.appendingPathComponent("units.json") else {
            logger.error("Shared widget container is unavailable.")
            return
        }
        for item in units where item.unit.xiaomi != nil {
            XiaomiTokenStore.shareLegacyToken(for: item.unit.id)
        }
        do {
            try JSONEncoder().encode(units).write(to: url, options: .atomic)
        } catch {
            logger.error("Could not publish the widget catalog: \(error.localizedDescription, privacy: .private)")
            return
        }
        reload()
    }

    static func reload() {
        guard !isTesting else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func lastFailure(for id: UUID) -> String? {
        guard let url = failureURL(for: id), let data = try? Data(contentsOf: url),
              let failure = try? JSONDecoder().decode(Failure.self, from: data),
              failure.expiresAt > .now else { return nil }
        return failure.message
    }

    static func recordFailure(_ message: String?, for id: UUID) {
        guard let url = failureURL(for: id) else { return }
        if let message {
            let failure = Failure(message: message, expiresAt: .now.addingTimeInterval(600))
            try? JSONEncoder().encode(failure).write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func failureURL(for id: UUID) -> URL? {
        container?.appendingPathComponent("\(id.uuidString).failure.json")
    }

    private struct Failure: Codable {
        let message: String
        let expiresAt: Date
    }
}
