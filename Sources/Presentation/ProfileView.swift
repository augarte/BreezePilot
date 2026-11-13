import SwiftUI

/// The toolbar button that opens the profile page. Both tabs show it in the same place.
struct ProfileToolbarButton: View {
    @State private var showing = false
    let library: ACLibrary

    var body: some View {
        Button("Profile", systemImage: "person.crop.circle") { showing = true }
            .sheet(isPresented: $showing) { ProfileView(library: library) }
    }
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editingRoom: ACRoom?
    @Bindable var library: ACLibrary

    private var summary: String {
        let acs = library.units.count, rooms = library.rooms.count, scenes = library.setups.count
        return "\(acs) \(acs == 1 ? "AC" : "ACs") · \(rooms) \(rooms == 1 ? "room" : "rooms") · \(scenes) \(scenes == 1 ? "scene" : "scenes")"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(BreezePilotPalette.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("My Home").font(.title3.weight(.semibold))
                            Text(summary).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Toggle("Reopen Last AC", isOn: $library.restoresScreen)
                } footer: {
                    Text("Start where you left off. Turn this off to always open the AC list.")
                }

                Section("Rooms") {
                    ForEach(library.rooms) { room in
                        Button {
                            editingRoom = room
                        } label: {
                            HStack {
                                Text(room.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Add Room", systemImage: "plus") { editingRoom = ACRoom() }
                }

                Section("About") {
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingRoom) { RoomEditor(room: $0, library: library) }
        }
    }
}

private struct RoomEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var confirmingRemoval = false
    let room: ACRoom
    let library: ACLibrary

    init(room: ACRoom, library: ACLibrary) {
        self.room = room
        self.library = library
        _name = State(initialValue: room.name)
    }

    private var existing: Bool { library.rooms.contains { $0.id == room.id } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicate: Bool { library.hasRoom(named: trimmedName, except: room.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Room name", text: $name)
                    if duplicate { Text("A room with this name already exists.").foregroundStyle(.secondary) }
                }
                if existing {
                    Section {
                        Button("Delete Room", role: .destructive) { confirmingRemoval = true }
                            .disabled(library.replacementRoom(for: room.id) == nil)
                    } footer: {
                        if library.replacementRoom(for: room.id) == nil {
                            Text("Keep at least one room for your air conditioners.")
                        }
                    }
                }
            }
            .navigationTitle(existing ? "Edit Room" : "Add Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = room
                        updated.name = trimmedName
                        library.save(updated)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || duplicate)
                }
            }
            .alert("Delete this room?", isPresented: $confirmingRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Room", role: .destructive) {
                    library.removeRoom(room.id)
                    dismiss()
                }
            } message: {
                if let replacement = library.replacementRoom(for: room.id) {
                    Text("ACs in this room will move to \(replacement.name).")
                }
            }
        }
    }
}
