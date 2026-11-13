import SwiftUI

struct ACListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ACListViewModel
    @Binding var addingUnit: Bool
    let library: ACLibrary
    let devices: ACDevices

    init(library: ACLibrary, devices: ACDevices, addingUnit: Binding<Bool>) {
        _addingUnit = addingUnit
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
                    LazyVStack(alignment: .leading, spacing: BreezeMetrics.sectionSpacing) {
                        ForEach(library.rooms) { room in
                            let units = library.units.filter { $0.roomID == room.id }
                            if !units.isEmpty { group(room.name, units: units) }
                        }
                    }
                    .breezePage()
                }
                .refreshable { await viewModel.refresh(library.units) }
            }
        }
        .background(BreezePilotPalette.canvas)
        .navigationTitle("Air Conditioners")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileToolbarButton(library: library).labelStyle(.iconOnly)
            }
        }
        .task(id: RefreshTrigger(units: library.units, phase: scenePhase)) {
            if scenePhase == .active { await viewModel.refresh(library.units) }
        }
    }

    private func group(_ name: String, units: [SavedAC]) -> some View {
        VStack(alignment: .leading, spacing: BreezeMetrics.cardSpacing) {
            Text(name)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(units) { unit in
                let status = viewModel.summaries[unit.id]
                let canPower = status?.powerWritable == true
                NavigationLink(value: unit.id) {
                    ACListCard(name: unit.name, status: status, loading: viewModel.loading,
                               reservesPowerButton: canPower)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("acListItem")
                // The power button sits over the card, not inside the link, so each stays its own control.
                .overlay(alignment: .topTrailing) {
                    if let status, canPower {
                        ACListPowerButton(name: unit.name, isOn: status.isOn,
                                          busy: viewModel.busy.contains(unit.id)) {
                            Task { await viewModel.togglePower(unit) }
                        }
                        .padding(BreezeMetrics.cardPadding)
                    }
                }
            }
        }
    }
}
