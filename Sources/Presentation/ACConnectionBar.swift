import SwiftUI

/// A quiet line that says whether the AC is reachable and when it was last read.
struct ACStatusLine: View {
    let viewModel: ACControlViewModel

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.activity != nil {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "wifi").accessibilityHidden(true)
            }
            Text(title).accessibilityIdentifier("connectionStatus")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if viewModel.activity == .writing { return "Applying AC change…" }
        if viewModel.activity == .reading { return "Reading AC status…" }
        guard let date = viewModel.updatedAt else { return "Connected to AC" }
        return "Connected · Updated at \(date.formatted(date: .omitted, time: .shortened))"
    }
}
