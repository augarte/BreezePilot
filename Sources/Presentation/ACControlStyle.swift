import SwiftUI

struct ACTemperatureStepIcon: View {
    let symbol: String
    let enabled: Bool
    var size: CGFloat = 48
    var symbolSize: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
            .background(.white.opacity(enabled ? 0.2 : 0.08), in: Circle())
    }
}

struct ACOptionAppearance: ViewModifier {
    let selected: Bool
    let available: Bool
    var cornerRadius: CGFloat = BreezeMetrics.controlRadius

    func body(content: Content) -> some View {
        content
            .foregroundStyle(selected ? Color.white : BreezePilotPalette.accent)
            .background(selected ? BreezePilotPalette.action : BreezePilotPalette.ice,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(available ? 1 : 0.45)
    }
}
