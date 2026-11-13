import SwiftUI

/// The control screen's main card: power, the set temperature and the room's readings.
struct ACTemperatureCard: View {
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize = 76.0
    let viewModel: ACControlViewModel
    let status: ACStatus
    let isXiaomi: Bool

    /// The temperature can't be changed while the AC is off or in a mode without a target.
    private var dimmed: Bool { !status.isOn || !status.isTemperatureMode }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Label {
                    Text(isXiaomi ? "Set temperature" : "Cooling target")
                } icon: {
                    Image(systemName: status.mode == .heat && isXiaomi ? "thermometer.sun" : "snowflake")
                        .foregroundStyle(BreezePilotPalette.gold)
                }
                .font(.headline)
                .opacity(dimmed ? 0.7 : 1)

                Spacer(minLength: 8)
                powerButton
            }

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
            .opacity(dimmed ? 0.6 : 1)

            if status.room.hasReading {
                Divider().overlay(.white.opacity(0.22))
                RoomConditionsView(conditions: status.room)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: BreezeMetrics.cardRadius)
                .fill(BreezePilotPalette.temperatureGradient)
                .saturation(dimmed ? 0.1 : 1)
        }
    }

    private var powerButton: some View {
        Button {
            Task { await viewModel.togglePower() }
        } label: {
            Image(systemName: "power")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 48, height: 48)
                .foregroundStyle(status.isOn ? BreezePilotPalette.action : Color.white)
                .background(.white.opacity(status.isOn ? 1 : 0.22), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isUpdating || !status.powerWritable)
        .opacity(status.powerWritable ? 1 : 0.4)
        .accessibilityLabel(status.isOn ? "Turn Off" : "Turn On")
        .accessibilityValue(status.isOn ? "AC is on" : "AC is off")
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
            ACTemperatureStepIcon(symbol: delta > 0 ? "plus" : "minus", enabled: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "Raise set temperature" : "Lower set temperature")
    }
}
