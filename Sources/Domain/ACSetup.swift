import Foundation

enum ACSetupIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    // Raw values are persisted and shared with the widget, so existing cases keep their names.
    case moon, home, departure, snowflake, sun
    case work, movie, cook, workout, reading, gaming, guests, party, evening, cozy, eco

    var id: Self { self }

    var symbol: String {
        switch self {
        case .moon: "moon.stars"
        case .home: "house"
        case .departure: "door.left.hand.open"
        case .snowflake: "snowflake"
        case .sun: "sun.max"
        case .work: "laptopcomputer"
        case .movie: "film"
        case .cook: "fork.knife"
        case .workout: "figure.run"
        case .reading: "book"
        case .gaming: "gamecontroller"
        case .guests: "person.2"
        case .party: "party.popper"
        case .evening: "sunset"
        case .cozy: "flame"
        case .eco: "leaf"
        }
    }

    /// What the scene is for, not what the icon looks like.
    var label: String {
        switch self {
        case .moon: "Sleep"
        case .home: "Home"
        case .departure: "Away"
        case .snowflake: "Cool Down"
        case .sun: "Morning"
        case .work: "Work"
        case .movie: "Movie Night"
        case .cook: "Cooking"
        case .workout: "Workout"
        case .reading: "Reading"
        case .gaming: "Gaming"
        case .guests: "Guests"
        case .party: "Party"
        case .evening: "Evening"
        case .cozy: "Cozy"
        case .eco: "Eco"
        }
    }
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
