import AppIntents
import SwiftUI
import WidgetKit

@main
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
    }
}

private struct ACWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ACWidgetEntry

    var body: some View {
        Group {
            if entry.readings.isEmpty {
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
            } else if family == .systemLarge {
                largeLayout
            } else if entry.readings.count == 1, let reading = entry.readings.first {
                ACWidgetTile(reading: reading, compact: family == .systemSmall,
                             linksToAC: family != .systemSmall, showsRefresh: true)
            } else {
                row(entry.readings)
            }
        }
        .tint(BreezePilotPalette.accent)
        .widgetURL(widgetURL)
    }

    private var widgetURL: URL? {
        if family == .systemSmall, let reading = entry.readings.first {
            return ACWidgetStore.controlURL(for: reading.id)
        }
        return ACWidgetStore.homeURL
    }

    private var largeLayout: some View {
        let usesGrid = entry.readings.count > 2
        return VStack(alignment: .leading, spacing: usesGrid ? 6 : 8) {
            widgetHeader
            Divider()
            if usesGrid {
                row(Array(entry.readings.prefix(2)))
                Divider()
                row(Array(entry.readings.dropFirst(2)))
            } else {
                ForEach(entry.readings) { reading in
                    ACWidgetTile(reading: reading, compact: false, linksToAC: true)
                    if reading.id != entry.readings.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var widgetHeader: some View {
        HStack(spacing: 4) {
            Label("Air Conditioners", systemImage: "snowflake")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(BreezePilotPalette.accent)
            Spacer(minLength: 0)
            ACWidgetRefreshButton(compact: false)
        }
    }

    private func row(_ readings: [ACWidgetReading]) -> some View {
        HStack(spacing: 10) {
            ForEach(readings) { reading in
                ACWidgetTile(reading: reading, compact: readings.count > 1, linksToAC: true,
                             showsRefresh: family != .systemLarge && reading.id == readings.last?.id)
                if reading.id != readings.last?.id { Divider() }
            }
        }
    }
}

private struct ACWidgetRefreshButton: View {
    let compact: Bool

    var body: some View {
        let diameter: CGFloat = compact ? 18 : 22
        Button(intent: RefreshACWidgetIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .invalidatableContent()
                .foregroundStyle(BreezePilotPalette.accent)
                .frame(width: diameter, height: diameter)
                .background(BreezePilotPalette.ice, in: Circle())
                .frame(width: compact ? 22 : 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Refresh air conditioner status")
    }
}

private struct ACWidgetTile: View {
    let reading: ACWidgetReading
    let compact: Bool
    let linksToAC: Bool
    var showsRefresh = false

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            if let status = reading.status, status.powerWritable {
                powerButton(status)
            }
            VStack(alignment: .leading, spacing: 2) {
                header
                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            name.layoutPriority(1)
            if let status = reading.status, !status.powerWritable {
                Text(status.isOn ? "On" : "Off")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.isOn ? BreezePilotPalette.accent : Color.secondary)
                    .transition(.identity)
            }
            if let failure = reading.failure {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text(failure))
            }
            if !compact, let roomName = reading.unit.roomName {
                Spacer(minLength: 0)
                Text(roomName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if showsRefresh && (!compact || reading.status == nil) {
                if compact || reading.unit.roomName == nil { Spacer(minLength: 0) }
                ACWidgetRefreshButton(compact: compact)
            }
        }
    }

    @ViewBuilder
    private var name: some View {
        let title = Text(reading.unit.name)
            .font(compact ? .caption.weight(.semibold) : .headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        if linksToAC {
            Link(destination: ACWidgetStore.controlURL(for: reading.id)) { title }
        } else {
            title
        }
    }

    @ViewBuilder
    private var controls: some View {
        if let status = reading.status {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                stepRow(.temperature,
                        value: temperatureValue(status),
                        decrease: temperatureIntent(-1, status: status),
                        increase: temperatureIntent(1, status: status))
                stepRow(.fan,
                        value: status.isOn ? status.fan?.selected?.label : nil,
                        decrease: fanIntent(-1, status: status),
                        increase: fanIntent(1, status: status))
            }
        } else {
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func powerButton(_ status: ACStatus) -> some View {
        Button(intent: SetACPowerIntent(unit: reading.unit, isOn: !status.isOn)) {
            VStack(spacing: 4) {
                Image(systemName: "power")
                    .font(.system(size: compact ? 15 : 20, weight: .semibold))
                Text(status.isOn ? "On" : "Off")
                    .font(.caption2.weight(.semibold))
                    .transition(.identity)
            }
            .foregroundStyle(status.isOn ? BreezePilotPalette.accent : Color.secondary)
            .frame(width: compact ? 29 : 44)
            .frame(maxHeight: .infinity)
            .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(status.isOn ? "Turn \(reading.unit.name) off" : "Turn \(reading.unit.name) on")
        .accessibilityValue(status.isOn ? "AC is on" : "AC is off")
    }

    private enum StepKind {
        case temperature, fan

        var icon: String { self == .temperature ? "thermometer.medium" : "fan" }
        var title: LocalizedStringKey { self == .temperature ? "Target temperature" : "Fan speed" }
    }

    private func stepRow<Intent: AppIntent>(
        _ kind: StepKind,
        value: String?,
        decrease: Intent?,
        increase: Intent?
    ) -> some View {
        let readout = HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .accessibilityHidden(true)
            Text(value ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .accessibilityLabel(Text(kind.title))
                .accessibilityValue(value ?? "Unavailable")
                .transition(.identity)
            if compact && showsRefresh && kind == .fan {
                Spacer(minLength: 0)
                ACWidgetRefreshButton(compact: true)
            }
        }
        .font((compact ? Font.caption2 : .caption).weight(.semibold))
        let buttons = HStack(spacing: 4) {
            stepButton(-1, kind: kind, intent: decrease)
            stepButton(1, kind: kind, intent: increase)
        }
        .buttonStyle(.plain)
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: 1) {
                    readout
                    buttons
                }
            } else {
                HStack {
                    readout
                    Spacer(minLength: 4)
                    buttons
                }
            }
        }
    }

    @ViewBuilder
    private func stepButton<Intent: AppIntent>(
        _ direction: Int,
        kind: StepKind,
        intent: Intent?
    ) -> some View {
        let symbol = direction < 0 ? "minus" : "plus"
        let icon = Image(systemName: symbol)
            .font(.system(size: compact ? 14 : 16, weight: .semibold))
            .frame(width: compact ? nil : 44, height: compact ? 30 : 41)
            .frame(maxWidth: compact ? .infinity : nil)
            .modifier(ACOptionAppearance(selected: false, available: intent != nil, cornerRadius: 9))
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
        guard status.isOn, status.isTemperatureMode, let target = status.target else { return nil }
        return "\(ACStatus.degrees(target))°C"
    }

    private func temperatureIntent(_ direction: Int, status: ACStatus) -> AdjustACWidgetTemperatureIntent? {
        guard let previous = status.target, let mode = status.mode,
              let target = status.adjusted(by: direction) else { return nil }
        return AdjustACWidgetTemperatureIntent(unit: reading.unit, target: target, previous: previous, mode: mode)
    }

    private func fanIntent(_ direction: Int, status: ACStatus) -> SetACWidgetFanSpeedIntent? {
        guard status.isOn, let mode = status.mode, let fan = status.fan else { return nil }
        let current = fan.selected.flatMap { fan.available.firstIndex(of: $0) }
        let index = current.map { $0 + direction } ?? (direction > 0 ? 0 : -1)
        guard fan.available.indices.contains(index) else { return nil }
        return SetACWidgetFanSpeedIntent(unit: reading.unit, speed: fan.available[index], mode: mode)
    }
}
