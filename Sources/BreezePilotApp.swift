import SwiftUI

private enum AppTab: Hashable { case airConditioners, setups }

@main
struct BreezePilotApp: App {
    @State private var library: ACLibrary
    @State private var tab = AppTab.airConditioners
    @State private var requestedSetupID: UUID?
    @State private var addingUnit = false
    @State private var addingScene = false
    private let devices: ACDevices

    init() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let fixture = ACUITestFixture(rawValue: environment["BREEZEPILOT_UI_TESTING"] ?? "") {
            _library = State(initialValue: fixture.makeLibrary())
            devices = fixture.makeDevices()
            return
        }
        if environment["BREEZEPILOT_UNIT_TESTING"] == "1",
           let defaults = UserDefaults(suiteName: "local.breezepilot.test-host") {
            _library = State(initialValue: ACLibrary(defaults: defaults, fallbackAddress: nil))
            devices = .local
            return
        }
        #endif
        _library = State(initialValue: ACLibrary())
        devices = .local
    }

    private var widgetCatalog: [WidgetAC] {
        library.units.map { unit in
            WidgetAC(unit: unit, roomName: library.rooms.first { $0.id == unit.roomID }?.name)
        }
    }

    var body: some Scene {
        WindowGroup {
            // The system tab bar is hidden so the layout is the same on every iOS version: tabs on the
            // left, a separate round add button on the right.
            TabView(selection: $tab) {
                Tab("Control", systemImage: "snowflake", value: AppTab.airConditioners) {
                    NavigationStack(path: Binding<[UUID]>(
                        get: { library.selectedUnitID.map { [$0] } ?? [] },
                        set: { library.select($0.last) }
                    )) {
                        ACListView(library: library, devices: devices, addingUnit: $addingUnit)
                            .navigationDestination(for: UUID.self) { id in
                                if let unit = library.units.first(where: { $0.id == id }),
                                   let address = LocalAddress(unit.address) {
                                    ControlView(unit: unit, address: address, library: library, devices: devices)
                                        .id(unit)
                                }
                            }
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }

                Tab("Scenes", systemImage: "square.stack", value: AppTab.setups) {
                    ACSetupsView(requestedSetupID: $requestedSetupID, addingScene: $addingScene,
                                 library: library, devices: devices)
                        .toolbarVisibility(.hidden, for: .tabBar)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingTabBar(selection: $tab) {
                    if tab == .setups && !library.units.isEmpty {
                        addingScene = true
                    } else {
                        addingUnit = true
                    }
                }
            }
            .sheet(isPresented: $addingUnit) {
                ConnectionView(unit: SavedAC(roomID: library.defaultRoom?.id), library: library, devices: devices)
            }
            .tint(BreezePilotPalette.accent)
            .onChange(of: widgetCatalog, initial: true) { _, catalog in
                ACWidgetStore.publish(catalog)
                ACSetupStore.reload()
            }
            .onChange(of: library.setups, initial: true) { _, setups in
                ACSetupStore.publish(setups)
            }
            .onOpenURL { url in
                guard url.scheme == ACWidgetStore.homeURL.scheme else { return }
                if url.host == ACWidgetStore.homeURL.host {
                    tab = .airConditioners
                    library.select(UUID(uuidString: url.lastPathComponent))
                } else if url.host == ACSetupStore.homeURL.host {
                    tab = .setups
                    requestedSetupID = UUID(uuidString: url.lastPathComponent)
                }
            }
        }
    }
}

private struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let add: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    item(.airConditioners, title: "Control", symbol: "snowflake")
                    item(.setups, title: "Scenes", symbol: "square.stack")
                }
                .padding(4)
                .glassEffect(.regular, in: .capsule)

                Spacer(minLength: 0)

                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .frame(width: 58, height: 58)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Add")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func item(_ tab: AppTab, title: LocalizedStringKey, symbol: String) -> some View {
        let selected = selection == tab
        return Button { selection = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.title3).frame(height: 24)
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(selected ? BreezePilotPalette.accent : Color.primary)
            .frame(width: 92, height: 50)
            .background(selected ? BreezePilotPalette.accent.opacity(0.14) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
