import SwiftUI

struct ACListCard: View {
    let name: String
    let status: ACStatus?
    let loading: Bool
    /// Leaves room for the power button the list lays over the card's top trailing corner.
    var reservesPowerButton = false

    private var active: Bool { status?.isOn == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let status, status.isOn {
                settingTiles(status)
            }

            if let room = status?.room, room.hasReading {
                RoomConditionsView(conditions: room)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .breezeCard()
        .contentShape(RoundedRectangle(cornerRadius: BreezeMetrics.cardRadius))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: status?.mode?.symbol ?? "snowflake")
                .font(.title3.weight(.semibold))
                .foregroundStyle(active ? BreezePilotPalette.accent : Color.secondary)
                .frame(width: BreezeMetrics.cardAccessory, height: BreezeMetrics.cardAccessory)
                .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: BreezeMetrics.tileRadius))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                operatingState
            }
            Spacer(minLength: 8)
            if reservesPowerButton {
                Color.clear.frame(width: BreezeMetrics.cardAccessory, height: BreezeMetrics.cardAccessory)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var operatingState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color(uiColor: .systemGreen) : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(stateLabel)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(active ? BreezePilotPalette.accent : Color.secondary)
    }

    private var stateLabel: String {
        guard let status else { return loading ? "Checking connection…" : "Unavailable" }
        guard status.isOn else { return "Off" }
        return status.mode.map { "On · \($0.label)" } ?? "On"
    }

    @ViewBuilder
    private func settingTiles(_ status: ACStatus) -> some View {
        let target = status.isTemperatureMode ? status.target : nil
        let fan = status.fan?.selected
        if target != nil || fan != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    settings(target: target, fan: fan)
                }
                VStack(alignment: .leading, spacing: 10) {
                    settings(target: target, fan: fan)
                }
            }
        }
    }

    @ViewBuilder
    private func settings(target: Int?, fan: FanSpeed?) -> some View {
        if let target {
            ACSettingTile(
                title: "Set temperature",
                value: "\(ACStatus.degrees(target))°C",
                icon: "thermometer.snowflake"
            )
        }
        if let fan {
            ACSettingTile(title: "Fan speed", value: fan.label, icon: "fan")
        }
    }
}

/// Turns one AC on or off straight from the list.
struct ACListPowerButton: View {
    let name: String
    let isOn: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(isOn ? Color.white : BreezePilotPalette.accent)
                } else {
                    Image(systemName: "power").font(.system(size: 18, weight: .bold))
                }
            }
            .frame(width: BreezeMetrics.cardAccessory, height: BreezeMetrics.cardAccessory)
            .foregroundStyle(isOn ? Color.white : BreezePilotPalette.accent)
            .background(isOn ? BreezePilotPalette.action : BreezePilotPalette.ice, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(isOn ? "Turn off \(name)" : "Turn on \(name)")
        .accessibilityValue(isOn ? "AC is on" : "AC is off")
    }
}

private struct ACSettingTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: BreezeMetrics.tileRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

private extension ClimateMode {
    var symbol: String {
        switch self {
        case .cool: "snowflake"
        case .heat: "sun.max"
        case .dry: "drop"
        case .fan: "fan"
        case .auto: "arrow.triangle.2.circlepath"
        case .humidify: "humidity"
        }
    }
}
