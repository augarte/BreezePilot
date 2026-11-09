import SwiftUI

@main
struct BreezePilotApp: App {
    @State private var library: ACLibrary
    private let devices: ACDevices

    init() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
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
            .tint(BreezePilotPalette.accent)
            .onChange(of: widgetCatalog, initial: true) { _, catalog in
                ACWidgetStore.publish(catalog)
            }
            .onOpenURL { url in
                guard url.scheme == ACWidgetStore.homeURL.scheme, url.host == ACWidgetStore.homeURL.host else { return }
                library.select(UUID(uuidString: url.lastPathComponent))
            }
        }
    }
}
