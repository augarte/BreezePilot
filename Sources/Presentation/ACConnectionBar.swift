import SwiftUI

struct ACConnectionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let viewModel: ACControlViewModel

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            HStack(spacing: 10) {
                Image(systemName: viewModel.status == nil ? "wifi" : "wifi.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(connectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("connectionStatus")

                    if let date = viewModel.updatedAt, viewModel.status != nil {
                        Text("Updated at \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                powerButton
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.activity != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isUpdating)
                .accessibilityLabel("Refresh")
            }
        }
    }

    private var connectionTitle: String {
        if viewModel.activity == .writing { return "Applying AC change" }
        if viewModel.activity == .reading { return "Reading AC status" }
        return viewModel.status == nil ? "AC unavailable" : "Connected to AC"
    }

    @ViewBuilder
    private var powerButton: some View {
        if let status = viewModel.status {
            Button(status.isOn ? "Turn Off" : "Turn On", systemImage: "power") {
                Task { await viewModel.togglePower() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.isUpdating || !status.powerWritable)
            .accessibilityValue(status.isOn ? "AC is on" : "AC is off")
        }
    }

}
