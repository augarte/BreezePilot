import AppIntents
import SwiftUI
import WidgetKit

struct ACSetupWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ACSetupStore.kind, intent: ACSetupWidgetConfiguration.self,
                               provider: ACSetupWidgetTimeline()) { entry in
            ACSetupWidgetView(entry: entry)
                .containerBackground(for: .widget) { BreezePilotPalette.canvas }
        }
        .configurationDisplayName("AC Scenes")
        .description("Run saved air conditioner scenes from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

struct ACSetupWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "AC Scenes"
    static let description = IntentDescription("Choose which scenes you can run from this widget.")

    @Parameter(title: "Scene 1", query: WidgetACSetupQuery()) var first: ACSetupEntity
    @Parameter(title: "Scene 2", query: WidgetACSetupQuery()) var second: ACSetupEntity
    @Parameter(title: "Scene 3", query: WidgetACSetupQuery()) var third: ACSetupEntity
    @Parameter(title: "Scene 4", query: WidgetACSetupQuery()) var fourth: ACSetupEntity

    init() {
        first = .unselected
        second = .unselected
        third = .unselected
        fourth = .unselected
    }

    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemLarge) {
                Summary { \.$first; \.$second; \.$third; \.$fourth }
            }
            Case(.systemMedium) {
                Summary { \.$first; \.$second }
            }
            DefaultCase {
                Summary { \.$first }
            }
        }
    }

    func setups(in family: WidgetFamily, catalog: [ACSetup]) -> [ACSetup] {
        let slots = switch family {
        case .systemLarge: [first, second, third, fourth]
        case .systemMedium: [first, second]
        default: [first]
        }
        var seen = Set<UUID>()
        return slots.compactMap { slot in
            guard slot.id != ACSetupEntity.unselected.id, seen.insert(slot.id).inserted else { return nil }
            return catalog.first { $0.id == slot.id }
        }
    }
}

struct WidgetACSetupQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ACSetupEntity] {
        let setups = try await ACSetupQuery().entities(for: identifiers)
        return identifiers.contains(ACSetupEntity.unselected.id) ? [.unselected] + setups : setups
    }

    func suggestedEntities() async throws -> [ACSetupEntity] {
        try await [.unselected] + ACSetupQuery().suggestedEntities()
    }

    func defaultResult() async throws -> ACSetupEntity? { .unselected }
}

struct ACSetupWidgetEntry: TimelineEntry {
    struct Card: Identifiable {
        let setup: ACSetup
        let summary: String
        var result: ACSetupRunResult?
        var id: UUID { setup.id }
    }

    let date: Date
    let cards: [Card]
    var hasSavedSetups = true

    static func sample(count: Int) -> Self {
        let examples: [(String, ACSetupIcon, String)] = [
            ("Sleep", .moon, "Bedroom 26°C · Living Room off"),
            ("Heading Out", .departure, "Turn off 3 ACs"),
            ("Back Home", .home, "Living Room 24°C"),
            ("Cool Down", .snowflake, "Cool 2 ACs")
        ]
        return .init(date: .now, cards: examples.prefix(count).map { name, icon, summary in
            .init(setup: ACSetup(name: name, icon: icon), summary: summary)
        })
    }
}

struct ACSetupWidgetTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ACSetupWidgetEntry {
        .sample(count: context.family == .systemLarge ? 4 : context.family == .systemMedium ? 2 : 1)
    }

    func snapshot(for configuration: ACSetupWidgetConfiguration, in context: Context) async -> ACSetupWidgetEntry {
        if context.isPreview { return placeholder(in: context) }
        return entry(for: configuration, in: context.family)
    }

    func timeline(for configuration: ACSetupWidgetConfiguration, in context: Context) async -> Timeline<ACSetupWidgetEntry> {
        Timeline(entries: [entry(for: configuration, in: context.family)], policy: .never)
    }

    private func entry(for configuration: ACSetupWidgetConfiguration, in family: WidgetFamily) -> ACSetupWidgetEntry {
        let catalog = ACSetupStore.catalog
        let names = Dictionary(ACWidgetStore.catalog.map { ($0.unit.id, $0.unit.name) }, uniquingKeysWith: { first, _ in first })
        let cards = configuration.setups(in: family, catalog: catalog).map { setup in
            ACSetupWidgetEntry.Card(setup: setup, summary: setup.summary(names: names),
                                    result: ACSetupStore.lastResult(for: setup))
        }
        return .init(date: .now, cards: cards, hasSavedSetups: !catalog.isEmpty)
    }
}

private struct ACSetupWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ACSetupWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Scenes", systemImage: "square.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BreezePilotPalette.accent)
            if entry.cards.isEmpty {
                Text(entry.hasSavedSetups ? "Choose a scene in Edit Widget." : "Create a scene in BreezePilot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else if family == .systemLarge {
                largeCards
            } else {
                row(entry.cards[...])
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(family == .systemSmall ? entry.cards.first.map { ACSetupStore.detailsURL(for: $0.id) }
                   ?? ACSetupStore.homeURL : ACSetupStore.homeURL)
    }

    @ViewBuilder
    private var largeCards: some View {
        let cards = entry.cards
        if cards.count <= 2 {
            ForEach(cards) { card in
                cardView(card, spacious: cards.count == 1)
            }
        } else {
            let firstRowCount = cards.count == 3 ? 1 : 2
            row(cards.prefix(firstRowCount))
            row(cards.dropFirst(firstRowCount))
        }
    }

    private func row(_ cards: ArraySlice<ACSetupWidgetEntry.Card>) -> some View {
        HStack(spacing: 6) {
            ForEach(cards) { card in
                cardView(card)
            }
        }
    }

    private func cardView(_ card: ACSetupWidgetEntry.Card, spacious: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if family == .systemSmall {
                cardTitle(card.setup, spacious: spacious)
            } else {
                Link(destination: ACSetupStore.detailsURL(for: card.id)) {
                    cardTitle(card.setup, spacious: spacious)
                }
            }
            if let result = card.result {
                Label(result.allApplied ? "Last run applied" : result.summary,
                      systemImage: result.allApplied ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(result.allApplied ? Color.secondary : .orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(card.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 1)
            Button(intent: RunACSetupIntent(setup: card.setup)) {
                Image(systemName: "play.fill")
                    .font(.system(size: spacious ? 19 : 15, weight: .semibold))
                    .invalidatableContent()
                    .frame(maxWidth: .infinity)
                    .frame(height: spacious ? 44 : 34)
                    .foregroundStyle(.white)
                    .background(BreezePilotPalette.action, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Run \(card.setup.name)")
        }
        .padding(spacious ? 12 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BreezePilotPalette.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func cardTitle(_ setup: ACSetup, spacious: Bool) -> some View {
        Label(setup.name, systemImage: setup.icon.symbol)
            .font((spacious ? Font.title2 : .subheadline).weight(.semibold))
            .foregroundStyle(BreezePilotPalette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

#if DEBUG
#Preview("Scenes · Small", as: .systemSmall) {
    ACSetupWidget()
} timeline: {
    ACSetupWidgetEntry.sample(count: 1)
}

#Preview("Scenes · Medium", as: .systemMedium) {
    ACSetupWidget()
} timeline: {
    ACSetupWidgetEntry.sample(count: 1)
    ACSetupWidgetEntry.sample(count: 2)
}

#Preview("Scenes · Large", as: .systemLarge) {
    ACSetupWidget()
} timeline: {
    ACSetupWidgetEntry.sample(count: 1)
    ACSetupWidgetEntry.sample(count: 2)
    ACSetupWidgetEntry.sample(count: 3)
    ACSetupWidgetEntry.sample(count: 4)
}
#endif
