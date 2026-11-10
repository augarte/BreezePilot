import Foundation

enum ACSetupIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    case moon, home, departure, snowflake, sun

    var id: Self { self }

    var symbol: String {
        switch self {
        case .moon: "moon.stars"
        case .home: "house"
        case .departure: "door.left.hand.open"
        case .snowflake: "snowflake"
        case .sun: "sun.max"
        }
    }

    var label: String { rawValue.capitalized }
}

struct ACSetup: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var revision = UUID()
    var name = ""
    var icon: ACSetupIcon = .moon
    var targets: [ACSetupTarget] = []

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !targets.isEmpty && targets.allSatisfy(\.hasChanges) &&
            Set(targets.map(\.id)).count == targets.count
    }

    func summary(names: [UUID: String]) -> String {
        if targets.count > 2 { return "\(targets.count) ACs" }
        return targets.map { target in
            "\(names[target.id] ?? target.unitName): \(target.summary)"
        }.joined(separator: " · ")
    }
}

struct ACSetupTarget: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var unitName: String
    var power: Bool?
    var mode: ClimateMode?
    var temperature: Int?
    var fan: FanSpeed?

    var hasChanges: Bool { power != nil || mode != nil || temperature != nil || fan != nil }

    var summary: String {
        if power == false { return "Off" }
        let fields = [
            power == true ? "On" : nil,
            mode?.label,
            temperature.map { ACStatus.degrees($0) + "°C" },
            fan.map { "Fan \($0.label)" }
        ].compactMap { $0 }
        return fields.isEmpty ? "Choose settings" : fields.joined(separator: " · ")
    }

    mutating func discardSettingsWhenOff() {
        guard power == false else { return }
        mode = nil
        temperature = nil
        fan = nil
    }
}

struct ACSetupRunResult: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let setupID: UUID
    let revision: UUID
    let date: Date
    let units: [UnitResult]

    struct UnitResult: Codable, Equatable, Identifiable, Sendable {
        enum Outcome: String, Codable, Sendable { case applied, failed, missing }

        let id: UUID
        let name: String
        let outcome: Outcome
        let confirmed: [String]
        var message: String?

        var canRetry: Bool { outcome == .failed }
    }

    var allApplied: Bool { !units.isEmpty && units.allSatisfy { $0.outcome == .applied } }
    var summary: String {
        "\(units.filter { $0.outcome == .applied }.count) of \(units.count) \(units.count == 1 ? "AC" : "ACs") updated"
    }
}
