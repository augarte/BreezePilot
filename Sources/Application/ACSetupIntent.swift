import AppIntents
import Foundation

struct ACSetupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "AC Scene"
    static let defaultQuery = ACSetupQuery()
    static let unselected = ACSetupEntity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                                          name: "None", icon: .moon)

    let id: UUID
    let name: String
    let icon: ACSetupIcon

    var displayRepresentation: DisplayRepresentation {
        if id == Self.unselected.id { return DisplayRepresentation(title: "None") }
        return DisplayRepresentation(title: "\(name)", image: .init(systemName: icon.symbol))
    }

    init(_ setup: ACSetup) {
        self.init(id: setup.id, name: setup.name, icon: setup.icon)
    }

    private init(id: UUID, name: String, icon: ACSetupIcon) {
        self.id = id
        self.name = name
        self.icon = icon
    }
}

struct ACSetupQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ACSetupEntity] {
        let catalog = ACSetupStore.catalog
        return identifiers.compactMap { id in catalog.first { $0.id == id }.map(ACSetupEntity.init) }
    }

    func suggestedEntities() async throws -> [ACSetupEntity] {
        ACSetupStore.catalog.map(ACSetupEntity.init)
    }
}

struct RunACSetupIntent: AppIntent {
    static let title: LocalizedStringResource = "Run AC Scene"
    static let description = IntentDescription("Apply the saved settings for one or more air conditioners.")

    @Parameter(title: "Scene") var setup: ACSetupEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$setup)")
    }

    init() {}

    init(setup: ACSetup) {
        self.setup = ACSetupEntity(setup)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let saved = ACSetupStore.catalog.first(where: { $0.id == setup.id }) else {
            throw RunACSetup.Failure(message: "This scene was removed. Choose another scene in BreezePilot.")
        }
        let result = try await RunACSetup(makeDevice: ACDevices.local.make)(saved, units: ACWidgetStore.catalog.map(\.unit))
        return .result(dialog: "\(saved.name): \(result.summary).")
    }
}
