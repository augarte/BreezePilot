import SwiftUI

struct ACModePicker: View {
    let viewModel: ACControlViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let status = viewModel.status
        let modes = status?.usesDeviceOptions == true
            ? ClimateMode.allCases.filter { status?.availableModes.contains($0) == true || status?.mode == $0 }
            : ClimateMode.selectable
        let layout = dynamicTypeSize.isAccessibilitySize || modes.count > 4
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        VStack(alignment: .leading, spacing: 12) {
            Label("Mode", systemImage: "air.conditioner.horizontal")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            layout {
                ForEach(modes, id: \.self) { mode in
                    ACOptionButton(
                        title: mode.label,
                        accessibilityTitle: "\(mode.label) mode",
                        selected: status?.mode == mode,
                        available: status?.isOn == true && status?.availableModes.contains(mode) == true,
                        busy: viewModel.isUpdating
                    ) {
                        Task { await viewModel.selectMode(mode) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Operating mode")
        }
        .breezeCard()
    }
}

struct ACFanCard: View {
    let viewModel: ACControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Fan speed", systemImage: "fan")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            let speeds = displayedSpeeds
            let named = speeds.filter { $0 == .auto || $0 == .silent }
            let numbered = speeds.filter { $0 != .auto && $0 != .silent }
            if !named.isEmpty { row(named) }
            if !numbered.isEmpty {
                let rowSize = numbered.count > 5 ? 4 : 5
                row(Array(numbered.prefix(rowSize)))
                if numbered.count > rowSize { row(Array(numbered.dropFirst(rowSize))) }
            }
            if let status = viewModel.status {
                if !status.isOn {
                    Text("Turn on the AC to adjust the fan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if status.fan?.available.isEmpty != false {
                    Text("Fan speed is unavailable in this mode.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .breezeCard()
    }

    private var displayedSpeeds: [FanSpeed] {
        guard let status = viewModel.status, status.usesDeviceOptions else { return FanSpeed.daikin }
        return FanSpeed.allCases.filter {
            status.fan?.available.contains($0) == true || status.fan?.selected == $0
        }
    }

    private func row(_ speeds: [FanSpeed]) -> some View {
        HStack(spacing: BreezeMetrics.controlSpacing) {
            ForEach(speeds, id: \.self) { fanButton($0) }
        }
    }

    private func fanButton(_ speed: FanSpeed) -> some View {
        let status = viewModel.status
        return ACOptionButton(
            title: speed.label,
            accessibilityTitle: "Fan speed \(speed.label)",
            selected: status?.fan?.selected == speed,
            available: status?.isOn == true && status?.fan?.available.contains(speed) == true,
            busy: viewModel.isUpdating
        ) {
            Task { await viewModel.selectFanSpeed(speed) }
        }
    }
}

struct ACExtrasCard: View {
    let features: ACFeatures
    let viewModel: ACControlViewModel
    let isXiaomi: Bool

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if isXiaomi, let eco = features.econo {
                    Toggle("Eco mode", isOn: Binding(
                        get: { eco },
                        set: { value in Task { await viewModel.selectSpecialOperation(value ? .econo : .off) } }
                    ))
                    .disabled(viewModel.isUpdating)
                    .padding(.trailing, 6)
                } else if features.specialOperation != nil {
                    Text("Special Operation").font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(SpecialOperation.allCases, id: \.self) { operation in
                            ACOptionButton(
                                title: operation.rawValue,
                                accessibilityTitle: operation.rawValue,
                                selected: features.specialOperation == operation,
                                available: features.supports(operation),
                                busy: viewModel.isUpdating
                            ) {
                                Task { await viewModel.selectSpecialOperation(operation) }
                            }
                        }
                    }
                }
                if let streamer = features.streamer {
                    Toggle("Streamer", isOn: Binding(
                        get: { streamer },
                        set: { value in Task { await viewModel.setStreamer(value) } }
                    ))
                    .disabled(viewModel.isUpdating)
                    .padding(.trailing, 6)
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Extras", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .breezeCard()
    }
}

private struct ACOptionButton: View {
    let title: String
    let accessibilityTitle: String
    let selected: Bool
    let available: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .modifier(ACOptionAppearance(selected: selected, available: available))
        }
        .buttonStyle(.plain)
        .disabled(!available || busy)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
