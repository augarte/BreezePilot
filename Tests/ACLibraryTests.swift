import Foundation
import Testing
@testable import BreezePilot

@MainActor
struct ACLibraryTests {
    @Test func newLibraryStartsEmptyWithLivingRoomAsTheDefault() throws {
        try withLibrary { library, _ in
            #expect(library.units.isEmpty)
            #expect(library.rooms.map(\.name) == ["Living Room", "Bedroom", "Bathroom", "Kitchen"])
            let unit = SavedAC(name: "Example AC", address: "10.20.30.40")
            library.save(unit)
            #expect(library.units.first?.roomID == library.defaultRoom?.id)
        }
    }

    @Test func migratesLegacyAddressAndRemembersTheSelectedUnit() throws {
        try withLibrary(prepare: { $0.set("10.20.30.40", forKey: "acAddress") }) { library, defaults in
            let unit = try #require(library.units.first)
            #expect(library.units.count == 1)
            #expect(unit.address == "10.20.30.40")
            #expect(unit.roomID == library.defaultRoom?.id)
            #expect(library.selectedUnitID == unit.id)
            #expect(ACLibrary(defaults: defaults, fallbackAddress: nil).selectedUnitID == unit.id)
        }
    }

    @Test func repairsLegacyUnitsWithMissingRooms() throws {
        let unit = SavedAC(name: "Example AC", address: "10.20.30.40", roomID: UUID())
        let legacyState = try JSONEncoder().encode(LegacyState(units: [unit], rooms: []))
        try withLibrary(prepare: { $0.set(legacyState, forKey: "acLibrary") }) { library, defaults in
            let room = try #require(library.defaultRoom)
            #expect(room.name == "Living Room")
            #expect(library.units.first?.roomID == room.id)
            #expect(ACLibrary(defaults: defaults, fallbackAddress: nil).units.first?.roomID == room.id)
        }
    }

    @Test func deletingARoomReassignsItsUnitsAndKeepsAtLeastOneRoom() throws {
        try withLibrary { library, _ in
            let bedroom = try #require(library.rooms.first { $0.name == "Bedroom" })
            let livingRoom = try #require(library.defaultRoom)
            library.save(SavedAC(name: "Example AC", address: "10.20.30.40", roomID: bedroom.id))

            library.removeRoom(bedroom.id)
            #expect(library.units.first?.roomID == livingRoom.id)

            for room in library.rooms where room.id != livingRoom.id {
                library.removeRoom(room.id)
            }
            library.removeRoom(livingRoom.id)
            #expect(library.rooms.map(\.id) == [livingRoom.id])
        }
    }

    @Test func disablingScreenRestorationOpensTheListAfterRestart() throws {
        try withLibrary { library, defaults in
            let unit = SavedAC(name: "Example AC", address: "10.20.30.40")
            library.save(unit)
            library.select(unit.id)
            library.restoresScreen = false

            let reopened = ACLibrary(defaults: defaults, fallbackAddress: nil)
            #expect(!reopened.restoresScreen)
            #expect(reopened.selectedUnitID == nil)
            #expect(reopened.units.map(\.id) == [unit.id])
        }
    }

    private func withLibrary(
        prepare: (UserDefaults) -> Void = { _ in },
        _ test: (ACLibrary, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "BreezePilotTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        prepare(defaults)
        try test(ACLibrary(defaults: defaults, fallbackAddress: nil), defaults)
    }

    private struct LegacyState: Encodable {
        let units: [SavedAC]
        let rooms: [ACRoom]
        let restoresScreen = true
    }
}
