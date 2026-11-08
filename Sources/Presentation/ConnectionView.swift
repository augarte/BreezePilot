import SwiftUI
import UIKit

struct ConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel: ACConnectionViewModel
    @State private var confirmingRemoval = false
    @State private var showingTokenHelp = false
    @FocusState private var connectionField: Field?
    let library: ACLibrary

    private enum Field { case address, token }

    init(unit: SavedAC, library: ACLibrary, devices: ACDevices) {
        _viewModel = State(initialValue: ACConnectionViewModel(unit: unit, library: library, devices: devices))
        self.library = library
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section("Air Conditioner") {
                    TextField("Name", text: $viewModel.draft.name)
                    if viewModel.existing {
                        LabeledContent("Brand", value: viewModel.manufacturer.rawValue)
                    } else {
                        Picker("Brand", selection: $viewModel.manufacturer) {
                            ForEach(ACConnectionViewModel.Manufacturer.allCases, id: \.self) { brand in
                                Text(brand.rawValue).tag(brand)
                            }
                        }
                        .disabled(viewModel.checking)
                    }
                    Picker("Room", selection: $viewModel.draft.roomID) {
                        ForEach(library.rooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                }

                connectionSection

                Section("Connection Help") {
                    Text("Use the same home network as the AC and allow Local Network access. Guest Wi-Fi may block devices from reaching each other.")
                    Button("Open iPhone Settings", systemImage: "arrow.up.right.square") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }

                if viewModel.existing {
                    Section {
                        Button("Remove AC", role: .destructive) { confirmingRemoval = true }
                            .disabled(viewModel.checking)
                    }
                }
            }
            .navigationTitle(viewModel.existing ? "Edit AC" : "Add AC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if viewModel.save() { dismiss() } }
                        .disabled(!viewModel.canSave)
                }
            }
            .alert("Remove this AC?", isPresented: $confirmingRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove AC", role: .destructive) { if viewModel.remove() { dismiss() } }
            } message: {
                Text("You can add it again using its local IP address.")
            }
            .sheet(isPresented: $showingTokenHelp) {
                XiaomiTokenHelpView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var connectionSection: some View {
        @Bindable var viewModel = viewModel

        return Section {
            TextField("Local IP address", text: $viewModel.draft.address)
                .keyboardType(.numbersAndPunctuation)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($connectionField, equals: .address)
                .disabled(viewModel.checking)

            if viewModel.manufacturer == .xiaomi {
                HStack(spacing: 8) {
                    SecureField(viewModel.existing ? "Replace device token" : "Xiaomi device token", text: $viewModel.tokenInput)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($connectionField, equals: .token)
                        .disabled(viewModel.checking)

                    Button {
                        connectionField = nil
                        showingTokenHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Where to find the Xiaomi device token")
                }
            }

            if viewModel.address == nil && !viewModel.draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Enter a local IPv4 address, such as 192.168.0.20.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.duplicate {
                Text("An AC with this address is already saved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                connectionField = nil
                Task { await viewModel.check() }
            } label: {
                HStack {
                    Text("Check Connection")
                    Spacer()
                    if viewModel.checking { ProgressView() }
                }
            }
            .disabled(!viewModel.canCheck)

            if let result = viewModel.result {
                Text(result).font(.subheadline)
            }
        } header: {
            Text("Connection")
        } footer: {
            if viewModel.manufacturer == .xiaomi {
                Text("Use the AC’s local IPv4 address and 32-character device token. Check the connection before saving. First setup uses internet access to look up the model.")
            } else {
                Text("Use the AC’s local IPv4 address from your router’s connected devices list.")
            }
        }
    }
}
