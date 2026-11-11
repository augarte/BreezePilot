import AppIntents
import SwiftUI
import WidgetKit

@main
struct BreezePilotWidgets: WidgetBundle {
    var body: some Widget {
        BreezePilotWidget()
        ACSetupWidget()
    }
}

struct BreezePilotWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ACWidgetStore.kind, intent: ACWidgetConfiguration.self,
                               provider: ACWidgetTimeline()) { entry in
            ACWidgetView(entry: entry)
                .containerBackground(for: .widget) { BreezePilotPalette.canvas }
        }
        .configurationDisplayName("Air Conditioners")
        .description("See and control your saved air conditioners.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}

private struct ACWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ACWidgetEntry

    var body: some View {
        Group {
            if let first = entry.readings.first {
                VStack(spacing: spacing) {
                    widgetHeader
                    units(first: first)
                }
                .padding(family == .systemSmall ? 8 : 10)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(BreezePilotPalette.accent)
        .widgetURL(widgetURL)
    }

    private var spacing: CGFloat { family == .systemSmall ? 4 : 6 }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "snowflake")
                .foregroundStyle(.tint)
            Text("Air Conditioners")
                .font(.headline)
            Text(entry.hasSavedUnits ? "Choose an AC in Edit Widget." : "Add an AC in BreezePilot to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
    }

    private var widgetURL: URL? {
        if family == .systemSmall, let reading = entry.readings.first {
            return ACWidgetStore.controlURL(for: reading.id)
        }
        return ACWidgetStore.homeURL
    }

    @ViewBuilder
    private func units(first: ACWidgetReading) -> some View {
        let readings = entry.readings
        switch (family, readings.count) {
        case (.systemSmall, _):
            ACWidgetTile(reading: first, style: .compact, linksToAC: false)
        case (.systemLarge, 1):
            ACWidgetTile(reading: first, style: .featured)
        case (.systemLarge, 2):
            VStack(spacing: spacing) {
                ForEach(readings) { reading in
                    ACWidgetTile(reading: reading, style: .wide)
                }
            }
        case (.systemLarge, 3):
            VStack(spacing: spacing) {
                ACWidgetTile(reading: first, style: .wide)
                row(readings.dropFirst())
            }
        case (.systemLarge, _):
            VStack(spacing: spacing) {
                row(readings.prefix(2))
                row(readings.dropFirst(2))
            }
        case (_, 1):
            ACWidgetTile(reading: first, style: .wide)
        default:
            row(readings[...])
        }
    }

    private var widgetHeader: some View {
        let small = family == .systemSmall
        let title: LocalizedStringKey = small ? "BreezePilot" : "Air Conditioners"
        return HStack(spacing: 4) {
            Label(title, systemImage: "snowflake")
                .font((small ? Font.caption : .subheadline).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(BreezePilotPalette.accent)
            Spacer(minLength: 0)
            ACWidgetRefreshButton(compact: small)
        }
        .padding(.horizontal, 2)
    }

    private func row(_ readings: ArraySlice<ACWidgetReading>) -> some View {
        HStack(spacing: spacing) {
            ForEach(readings) { reading in
                ACWidgetTile(reading: reading, style: .compact)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ACWidgetRefreshButton: View {
    let compact: Bool

    var body: some View {
        let diameter: CGFloat = compact ? 22 : 26
        Button(intent: RefreshACWidgetIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .invalidatableContent()
                .foregroundStyle(BreezePilotPalette.accent)
                .frame(width: diameter, height: diameter)
                .background(BreezePilotPalette.ice, in: Circle())
                .frame(width: compact ? 26 : 32, height: diameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Refresh air conditioner status")
    }
}

private struct ACWidgetTile: View {
    enum Style {
        case compact, wide, featured

        var powerWidth: CGFloat {
            switch self {
            case .compact: 25
            case .wide: 42
            case .featured: 52
            }
        }
    }

    let reading: ACWidgetReading
    let style: Style
    var linksToAC = true

    private var compact: Bool { style == .compact }

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            if let status = reading.status {
                power(status)
            }
            VStack(alignment: .leading, spacing: style == .featured ? 8 : 4) {
                header
                if let status = reading.status {
                    if style == .featured, status.room.hasReading {
                        RoomConditionsView(conditions: status.room)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    controls(status)
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(compact ? 4 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(BreezePilotPalette.surface, in: RoundedRectangle(cornerRadius: compact ? 12 : 15))
    }

    private var header: some View {
        HStack(spacing: 4) {
            name.layoutPriority(1)
            if let failure = reading.failure {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text(failure))
            }
        }
    }

    @ViewBuilder
    private var name: some View {
        let title = Text(reading.unit.name)
            .font((compact ? Font.caption : style == .featured ? .title3 : .subheadline).weight(.semibold))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        if linksToAC {
            Link(destination: ACWidgetStore.controlURL(for: reading.id)) { title }
        } else {
            title
        }
    }

    private func controls(_ status: ACStatus) -> some View {
        VStack(spacing: style == .featured ? 7 : 4) {
            stepRow(.temperature,
                    value: temperatureValue(status),
                    decrease: temperatureIntent(-1, status: status),
                    increase: temperatureIntent(1, status: status))
            stepRow(.fan,
                    value: status.isOn ? status.fan?.selected?.label : nil,
                    decrease: fanIntent(-1, status: status),
                    increase: fanIntent(1, status: status))
        }
    }

    @ViewBuilder
    private func power(_ status: ACStatus) -> some View {
        if status.powerWritable {
            Button(intent: SetACPowerIntent(unit: reading.unit, isOn: !status.isOn)) {
                powerLabel(status)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(status.isOn ? "Turn \(reading.unit.name) off" : "Turn \(reading.unit.name) on")
            .accessibilityValue(status.isOn ? "AC is on" : "AC is off")
        } else {
            powerLabel(status)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.isOn ? "AC is on" : "AC is off")
        }
    }

    private func powerLabel(_ status: ACStatus) -> some View {
        let highlighted = status.isOn && status.powerWritable
        return VStack(spacing: 3) {
            Image(systemName: "power")
                .font(.system(size: compact ? 14 : style == .featured ? 23 : 18, weight: .semibold))
            Text(status.isOn ? "On" : "Off")
                .font(.caption2.weight(.semibold))
                .transition(.identity)
        }
        .foregroundStyle(highlighted ? BreezePilotPalette.accent : Color.secondary)
        .frame(width: style.powerWidth)
        .frame(maxHeight: .infinity)
        .background(highlighted ? BreezePilotPalette.ice : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    private enum StepKind {
        case temperature, fan

        var icon: String { self == .temperature ? "thermometer.medium" : "fan" }
        var title: LocalizedStringKey { self == .temperature ? "Target temperature" : "Fan speed" }
        var shortTitle: LocalizedStringKey { self == .temperature ? "Set temperature" : "Fan speed" }
    }

    private func stepRow<Intent: AppIntent>(
        _ kind: StepKind,
        value: String?,
        decrease: Intent?,
        increase: Intent?
    ) -> some View {
        HStack(spacing: compact ? 2 : 5) {
            stepButton(-1, kind: kind, intent: decrease)
            stepReadout(kind, value: value)
            stepButton(1, kind: kind, intent: increase)
        }
        .buttonStyle(.plain)
        .padding(2)
        .frame(maxHeight: .infinity)
        .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: 9))
    }

    private func stepReadout(_ kind: StepKind, value: String?) -> some View {
        let isPending = kind == .temperature && reading.pendingTemperature != nil && value != nil
        return HStack(spacing: compact ? 2 : 5) {
            Image(systemName: kind.icon)
                .font(.system(size: compact ? 9 : 13))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                if !compact {
                    Text(kind.shortTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(value ?? "—")
                    .font(.system(size: compact ? 11 : style == .featured ? 24 : 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isPending ? BreezePilotPalette.accent : value == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.identity)
            }
        }
        .frame(minWidth: compact ? nil : 104, alignment: compact ? .center : .leading)
        .frame(width: compact ? 41 : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.title))
        .accessibilityValue(isPending ? "\(value ?? ""), pending" : value ?? "Unavailable")
    }

    @ViewBuilder
    private func stepButton<Intent: AppIntent>(
        _ direction: Int,
        kind: StepKind,
        intent: Intent?
    ) -> some View {
        let symbol = direction < 0 ? "minus" : "plus"
        let icon = Image(systemName: symbol)
            .font(.system(size: compact ? 13 : 17, weight: .semibold))
            .foregroundStyle(BreezePilotPalette.accent.opacity(intent == nil ? 0.4 : 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if intent != nil {
                    RoundedRectangle(cornerRadius: 7).fill(BreezePilotPalette.surface)
                }
            }
        if let intent {
            Button(intent: intent) {
                icon.contentShape(Rectangle())
            }
            .accessibilityLabel(stepAccessibilityLabel(direction, kind: kind))
        } else {
            icon.accessibilityHidden(true)
        }
    }

    private func stepAccessibilityLabel(_ direction: Int, kind: StepKind) -> Text {
        switch kind {
        case .temperature:
            direction < 0 ? Text("Lower \(reading.unit.name) target temperature") : Text("Raise \(reading.unit.name) target temperature")
        case .fan:
            direction < 0 ? Text("Lower \(reading.unit.name) fan speed") : Text("Raise \(reading.unit.name) fan speed")
        }
    }

    private func temperatureValue(_ status: ACStatus) -> String? {
        guard status.isOn, status.isTemperatureMode,
              let target = reading.pendingTemperature ?? status.target else { return nil }
        return "\(ACStatus.degrees(target))°C"
    }

    private func temperatureIntent(_ direction: Int, status: ACStatus) -> AdjustACWidgetTemperatureIntent? {
        guard let confirmed = status.target, let mode = status.mode, let limits = status.limits else { return nil }
        let previous = reading.pendingTemperature ?? confirmed
        guard let target = status.adjusted(by: direction, from: previous) else { return nil }
        return AdjustACWidgetTemperatureIntent(unit: reading.unit, target: target, previous: previous,
                                               mode: mode, limits: limits, observedAt: reading.observedAt,
                                               confirmed: confirmed)
    }

    private func fanIntent(_ direction: Int, status: ACStatus) -> SetACWidgetFanSpeedIntent? {
        guard status.isOn, let mode = status.mode, let fan = status.fan else { return nil }
        let current = fan.selected.flatMap { fan.available.firstIndex(of: $0) }
        let index = current.map { $0 + direction } ?? (direction > 0 ? 0 : -1)
        guard fan.available.indices.contains(index) else { return nil }
        return SetACWidgetFanSpeedIntent(unit: reading.unit, speed: fan.available[index], mode: mode)
    }
}
