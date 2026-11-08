import SwiftUI

struct ACTemperatureCard: View {
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize = 76.0
    let viewModel: ACControlViewModel
    let isXiaomi: Bool

    var body: some View {
        VStack(spacing: 16) {
            Label {
                Text(isXiaomi ? "Set temperature" : "Cooling target")
            } icon: {
                Image(systemName: viewModel.status?.mode == .heat && isXiaomi ? "thermometer.sun" : "snowflake")
                    .foregroundStyle(BreezePilotPalette.gold)
            }
            .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    temperatureButton(delta: -1)
                    targetValue
                        .frame(maxWidth: .infinity)
                    temperatureButton(delta: 1)
                }
                VStack(spacing: 10) {
                    targetValue
                    HStack(spacing: 22) {
                        temperatureButton(delta: -1)
                        temperatureButton(delta: 1)
                    }
                }
            }

            if let room = viewModel.status?.room, room.hasReading {
                Divider().overlay(.white.opacity(0.22))
                RoomConditionsView(conditions: room)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [BreezePilotPalette.action, BreezePilotPalette.navy],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var targetValue: some View {
        let target = viewModel.displayedTarget
        return Text(target.map { ACStatus.degrees($0) + "°" } ?? "—")
            .font(.system(size: temperatureSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .fixedSize()
            .accessibilityLabel(target.map { ACStatus.degrees($0) + " degrees Celsius" } ?? "Target unavailable")
            .accessibilityIdentifier("coolingTarget")
    }

    private func temperatureButton(delta: Int) -> some View {
        let enabled = viewModel.canAdjust(by: delta)
        return Button {
            viewModel.adjust(by: delta)
        } label: {
            Image(systemName: delta > 0 ? "plus" : "minus")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
                .background(.white.opacity(enabled ? 0.2 : 0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "Raise set temperature" : "Lower set temperature")
    }

}
