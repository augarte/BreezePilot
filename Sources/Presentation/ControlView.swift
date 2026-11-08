import SwiftUI

struct ControlView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingConnection = false
    @State private var viewModel: ACControlViewModel
    let unit: SavedAC
    let library: ACLibrary
    let devices: ACDevices

    init(unit: SavedAC, address: LocalAddress, library: ACLibrary, devices: ACDevices) {
        self.unit = unit
        self.library = library
        self.devices = devices
        _viewModel = State(initialValue: ACControlViewModel(device: devices.make(unit, address)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ACConnectionBar(viewModel: viewModel)
                Group {
                    if unit.xiaomi == nil || viewModel.status != nil {
                        ACModePicker(viewModel: viewModel)
                    }
                    ACTemperatureCard(viewModel: viewModel, isXiaomi: unit.xiaomi != nil)
                        .saturation(isTemperatureInactive ? 0 : 1)
                        .opacity(isTemperatureInactive ? 0.72 : 1)
                    if unit.xiaomi == nil || viewModel.status?.fan != nil {
                        ACFanCard(viewModel: viewModel)
                    }
                    if let features = viewModel.status?.features,
                       features.specialOperation != nil || features.streamer != nil {
                        ACExtrasCard(features: features, viewModel: viewModel, isXiaomi: unit.xiaomi != nil)
                    }
                }
                .disabled(isPoweredOff)
                .saturation(isPoweredOff ? 0 : 1)
                .opacity(isPoweredOff ? 0.72 : 1)
                if let message = viewModel.message {
                    Label(message, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("connectionMessage")
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await viewModel.refresh() }
        .navigationTitle(unit.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit AC", systemImage: "gearshape") { showingConnection = true }
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.isUpdating)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active && !showingConnection {
                Task { await viewModel.refresh() }
            }
        }
        .sheet(isPresented: $showingConnection, onDismiss: {
            Task { await viewModel.refresh() }
        }) {
            ConnectionView(unit: unit, library: library, devices: devices)
        }
    }

    private var isPoweredOff: Bool { viewModel.status?.isOn == false }
    private var isTemperatureInactive: Bool {
        viewModel.status.map { $0.isOn && !$0.isTemperatureMode } ?? false
    }
}
