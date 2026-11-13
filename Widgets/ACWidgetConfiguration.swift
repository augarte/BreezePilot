import AppIntents
import WidgetKit

enum LargeACWidgetLayout: String, AppEnum {
    case twoUnits
    case fourUnits

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .twoUnits: "2 Air Conditioners",
        .fourUnits: "4 Air Conditioners"
    ]
}

struct ACWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Air Conditioners"
    static let description = IntentDescription("Choose which air conditioners to show.")

    @Parameter(title: "AC 1", query: WidgetAirConditionerQuery()) var first: AirConditionerEntity?
    @Parameter(title: "AC 2", query: WidgetAirConditionerQuery()) var second: AirConditionerEntity?
    @Parameter(title: "AC 3", query: WidgetAirConditionerQuery()) var third: AirConditionerEntity?
    @Parameter(title: "AC 4", query: WidgetAirConditionerQuery()) var fourth: AirConditionerEntity?
    // Retain the saved parameter for widget configurations created before layouts were automatic.
    @Parameter(title: "Layout", default: .twoUnits) var largeLayout: LargeACWidgetLayout

    init() {
        first = .unselected
        second = .unselected
        third = .unselected
        fourth = .unselected
    }

    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemLarge) {
                Summary {
                    \.$first
                    \.$second
                    \.$third
                    \.$fourth
                }
            }
            Case(.systemMedium) {
                Summary {
                    \.$first
                    \.$second
                }
            }
            DefaultCase {
                Summary { \.$first }
            }
        }
    }

    func units(in family: WidgetFamily, catalog: [WidgetAC]) -> [WidgetAC] {
        let slots = switch family {
        case .systemLarge: [first, second, third, fourth]
        case .systemMedium: [first, second]
        default: [first]
        }

        var seen = Set<UUID>()
        return slots.compactMap { slot in
            guard let id = slot?.id else { return nil }
            guard id != AirConditionerEntity.unselected.id, seen.insert(id).inserted else { return nil }
            return catalog.first { $0.unit.id == id }
        }
    }
}

struct WidgetAirConditionerQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AirConditionerEntity] {
        let units = try await AirConditionerQuery().entities(for: identifiers)
        return identifiers.contains(AirConditionerEntity.unselected.id) ? [.unselected] + units : units
    }

    func suggestedEntities() async throws -> [AirConditionerEntity] {
        try await [.unselected] + AirConditionerQuery().suggestedEntities()
    }

    func defaultResult() async -> AirConditionerEntity? { .unselected }
}
