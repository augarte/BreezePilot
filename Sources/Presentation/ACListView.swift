import SwiftUI

struct ACListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var addingUnit = false
    @State private var showingSettings = false
    @State private var viewModel: ACListViewModel
    let library: ACLibrary
    let devices: ACDevices

    init(library: ACLibrary, devices: ACDevices) {
        self.library = library
        self.devices = devices
        _viewModel = State(initialValue: ACListViewModel(makeDevice: devices.make))
    }

    private struct RefreshTrigger: Equatable {
        let units: [SavedAC]
        let phase: ScenePhase
    }

    var body: some View {
        Group {
            if library.units.isEmpty {
                ACEmptyStateView(
                    artwork: .emptyACList,
                    title: "No ACs yet",
                    message: Text("Add an air conditioner using its local IP address."),
                    primaryAction: .init(title: "Add AC") { addingUnit = true },
                    primaryIcon: "plus"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(library.rooms) { room in
                            let units = library.units.filter { $0.roomID == room.id }
                            if !units.isEmpty { group(room.name, units: units) }
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await viewModel.refresh(library.units) }
            }
        }
        .background(BreezePilotPalette.canvas)
        .navigationTitle("Air Conditioners")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add AC", systemImage: "plus") { addingUnit = true }
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $addingUnit) {
            ConnectionView(unit: SavedAC(roomID: library.defaultRoom?.id), library: library, devices: devices)
        }
        .sheet(isPresented: $showingSettings) {
            LibrarySettingsView(library: library)
        }
        .task(id: RefreshTrigger(units: library.units, phase: scenePhase)) {
            if scenePhase == .active { await viewModel.refresh(library.units) }
        }
    }

    private func group(_ name: String, units: [SavedAC]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(name)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(units) { unit in
                NavigationLink(value: unit.id) {
                    ACListCard(
                        name: unit.name,
                        status: viewModel.summaries[unit.id],
                        loading: viewModel.loading
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("acListItem")
            }
        }
    }

}
