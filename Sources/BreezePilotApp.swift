import SwiftUI

@main
struct BreezePilotApp: App {
    @State private var library: ACLibrary
    @State private var tab = Tab.airConditioners
    @State private var requestedSetupID: UUID?
    private let devices: ACDevices

    private enum Tab { case airConditioners, setups }

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
            TabView(selection: $tab) {
                NavigationStack(path: Binding<[UUID]>(
                    get: { library.selectedUnitID.map { [$0] } ?? [] },
                    set: { library.select($0.last) }
                )) {
                    ACListView(library: library, devices: devices)
                        .navigationDestination(for: UUID.self) { id in
                            if let unit = library.units.first(where: { $0.id == id }),
                               let address = LocalAddress(unit.address) {
                                ControlView(unit: unit, address: address, library: library, devices: devices)
                                    .id(unit)
                            }
                        }
                }
                .tabItem { Label("Control", systemImage: "snowflake") }
                .tag(Tab.airConditioners)

                ACSetupsView(requestedSetupID: $requestedSetupID, library: library, devices: devices)
                    .tabItem { Label("Scenes", systemImage: "square.stack") }
                    .tag(Tab.setups)
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
