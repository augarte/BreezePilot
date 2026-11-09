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
        _viewModel = State(initialValue: ACControlViewModel(device: devices.make(unit, address), unitID: unit.id))
    }

    var body: some View {
        Group {
            if let status = viewModel.status {
                controls(status)
            } else if viewModel.isConnecting {
                ProgressView("Connecting to AC…")
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BreezePilotPalette.canvas)
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

    private func controls(_ status: ACStatus) -> some View {
        let isPoweredOff = !status.isOn
        let isTemperatureInactive = status.isOn && !status.isTemperatureMode
        let isXiaomi = unit.xiaomi != nil

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ACConnectionBar(status: status, viewModel: viewModel)
                Group {
                    ACModePicker(viewModel: viewModel)
                    ACTemperatureCard(viewModel: viewModel, isXiaomi: isXiaomi)
                        .saturation(isTemperatureInactive ? 0 : 1)
                        .opacity(isTemperatureInactive ? 0.72 : 1)
                    if !isXiaomi || status.fan != nil {
                        ACFanCard(viewModel: viewModel)
                    }
                    if status.features.specialOperation != nil || status.features.streamer != nil {
                        ACExtrasCard(features: status.features, viewModel: viewModel, isXiaomi: isXiaomi)
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
        .refreshable { await viewModel.refresh() }
    }

    private var unavailable: some View {
        ACEmptyStateView(
            artwork: .acUnavailable,
            title: "AC unavailable",
            message: Text(viewModel.message ?? ACDeviceError.unreachable.localizedDescription),
            primaryAction: .init(title: "Try Again") {
                Task { await viewModel.refresh() }
            },
            primaryIcon: "arrow.clockwise",
            secondaryAction: .init(title: "Edit Connection") { showingConnection = true },
            titleIdentifier: "connectionStatus",
            messageIdentifier: "connectionMessage"
        )
    }
}
