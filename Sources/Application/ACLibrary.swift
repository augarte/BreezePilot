import Foundation
import Observation
import OSLog

struct SavedAC: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var address = ""
    var roomID: UUID?
    var xiaomi: XiaomiProfile?
}

struct ACRoom: Codable, Identifiable {
    var id = UUID()
    var name = ""
}

@MainActor @Observable
final class ACLibrary {
    private static let livingRoomName = "Living Room"

    private struct SavedState: Codable {
        var units: [SavedAC] = []
        var rooms = ["Living Room", "Bedroom", "Bathroom", "Kitchen"].map { ACRoom(name: $0) }
        var restoresScreen = true
        var lastUnitID: UUID?
    }

    private static let storageKey = "acLibrary"
    private static let setupsKey = "acSetups"
    private let defaults: UserDefaults
    private var state: SavedState
    private(set) var selectedUnitID: UUID?
    private(set) var setups: [ACSetup]

    var units: [SavedAC] { state.units }
    var rooms: [ACRoom] { state.rooms }
    var defaultRoom: ACRoom? { preferredRoom(in: rooms) }

    var restoresScreen: Bool {
        get { state.restoresScreen }
        set {
            state.restoresScreen = newValue
            persist()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        fallbackAddress: String? = ProcessInfo.processInfo.environment["DAIKIN_ADDRESS"]
    ) {
        self.defaults = defaults
        setups = Self.load([ACSetup].self, forKey: Self.setupsKey, from: defaults) ?? []
        if let saved = Self.load(SavedState.self, forKey: Self.storageKey, from: defaults) {
            state = saved
            if saved.restoresScreen {
                selectedUnitID = saved.units.first { $0.id == saved.lastUnitID }?.id
            }
            repairRoomAssignments()
        } else {
            state = SavedState()
            let oldAddress = defaults.string(forKey: "acAddress") ?? fallbackAddress
            if let oldAddress, let address = LocalAddress(oldAddress) {
                let unit = SavedAC(name: "Daikin AC", address: address.value, roomID: defaultRoom?.id)
                state.units = [unit]
                selectedUnitID = unit.id
            }
            persist()
        }
        defaults.removeObject(forKey: "acAddress")
    }

    /// Suffix of the key that keeps saved data this version couldn't read.
    static let unreadableSuffix = ".unreadable"

    /// Reads a saved value. Data that exists but can't be decoded is copied aside first, because the
    /// library starts from defaults in that case and its next save would otherwise destroy the original.
    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            defaults.set(data, forKey: key + unreadableSuffix)
            Logger(subsystem: "local.daikin.directcontrol", category: "Library")
                .error("Could not read \(key, privacy: .public); kept a copy: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func select(_ id: UUID?) {
        selectedUnitID = units.first { $0.id == id }?.id
        persist()
    }

    func hasUnit(at address: LocalAddress, except id: UUID) -> Bool {
        units.contains { $0.address == address.value && $0.id != id }
    }

    func save(_ unit: SavedAC) {
        var unit = unit
        if !rooms.contains(where: { $0.id == unit.roomID }) { unit.roomID = defaultRoom?.id }
        if let index = state.units.firstIndex(where: { $0.id == unit.id }) {
            state.units[index] = unit
        } else {
            state.units.append(unit)
        }
        persist()
    }

    func removeUnit(_ id: UUID) {
        state.units.removeAll { $0.id == id }
        if selectedUnitID == id { selectedUnitID = nil }
        persist()
    }

    @discardableResult
    func saveSetup(_ draft: ACSetup) -> Bool {
        guard draft.canSave else { return false }
        var setup = draft
        setup.name = setup.name.trimmingCharacters(in: .whitespacesAndNewlines)
        setup.revision = UUID()
        for index in setup.targets.indices {
            let id = setup.targets[index].id
            if let unit = units.first(where: { $0.id == id }) {
                setup.targets[index].unitName = unit.name
            }
            setup.targets[index].discardSettingsWhenOff()
        }
        if let index = setups.firstIndex(where: { $0.id == setup.id }) {
            setups[index] = setup
        } else {
            setups.append(setup)
        }
        persistSetups()
        return true
    }

    func removeSetup(_ id: UUID) {
        setups.removeAll { $0.id == id }
        persistSetups()
    }

    private func persistSetups() {
        if let data = try? JSONEncoder().encode(setups) {
            defaults.set(data, forKey: Self.setupsKey)
        }
    }

    func hasRoom(named name: String, except id: UUID) -> Bool {
        rooms.contains { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func save(_ room: ACRoom) {
        if let index = state.rooms.firstIndex(where: { $0.id == room.id }) {
            state.rooms[index] = room
        } else {
            state.rooms.append(room)
        }
        persist()
    }

    func replacementRoom(for id: UUID) -> ACRoom? {
        preferredRoom(in: rooms.filter { $0.id != id })
    }

    func removeRoom(_ id: UUID) {
        guard let replacement = replacementRoom(for: id) else { return }
        state.rooms.removeAll { $0.id == id }
        for index in state.units.indices where state.units[index].roomID == id {
            state.units[index].roomID = replacement.id
        }
        persist()
    }

    private func preferredRoom(in rooms: [ACRoom]) -> ACRoom? {
        rooms.first { $0.name.localizedCaseInsensitiveCompare(Self.livingRoomName) == .orderedSame }
            ?? rooms.first
    }

    private func repairRoomAssignments() {
        var changed = rooms.isEmpty
        if changed { state.rooms = [ACRoom(name: Self.livingRoomName)] }
        if let room = defaultRoom {
            let roomIDs = Set(rooms.map(\.id))
            for index in state.units.indices where state.units[index].roomID.map(roomIDs.contains) != true {
                state.units[index].roomID = room.id
                changed = true
            }
        }
        if changed { persist() }
    }

    private func persist() {
        state.lastUnitID = restoresScreen ? selectedUnitID : nil
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
