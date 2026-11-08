import SwiftUI

@main
struct BreezePilotApp: App {
    @State private var library = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BREEZEPILOT_UNIT_TESTING"] == "1",
           let defaults = UserDefaults(suiteName: "local.breezepilot.test-host") {
            return ACLibrary(defaults: defaults, fallbackAddress: nil)
        }
        #endif
        return ACLibrary()
    }()
    private let devices = ACDevices(
        make: { unit, address in
            if let profile = unit.xiaomi {
                return XiaomiClient(address: address, profile: profile, credentials: .stored(unit.id))
            }
            return DaikinClient(address: address)
        },
        xiaomiSetup: XiaomiLocalSetup()
    )

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
        }
    }
}
