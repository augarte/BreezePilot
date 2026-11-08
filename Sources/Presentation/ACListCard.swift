import SwiftUI

struct ACListCard: View {
    let name: String
    let status: ACStatus?
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BreezePilotPalette.surface, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.title3.weight(.semibold))
                .foregroundStyle(BreezePilotPalette.accent)
                .frame(width: 46, height: 46)
                .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                operatingState
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var operatingState: some View {
        let active = status?.isOn == true
        return HStack(spacing: 6) {
            Circle()
                .fill(active ? BreezePilotPalette.gold : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(stateLabel)
                .font(.caption.weight(.semibold))
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
                value: "\(ACStatus.degrees(target)) °C",
                icon: "thermometer.snowflake"
            )
        }
        if let fan {
            ACSettingTile(title: "Fan speed", value: fan.label, icon: "fan")
        }
    }
}

private struct ACSettingTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}
