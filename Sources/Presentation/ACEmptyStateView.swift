import SwiftUI

struct ACEmptyStateView: View {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    var artwork: BreezeIllustration.Artwork?
    /// Shown in place of artwork on screens that have no illustration.
    var symbol: String?
    let title: LocalizedStringKey
    let message: Text
    var primaryAction: Action?
    var primaryIcon = "plus"
    var secondaryAction: Action?
    var titleIdentifier = "emptyStateTitle"
    var messageIdentifier = "emptyStateMessage"

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(spacing: 20) {
            if let artwork {
                BreezeIllustration(artwork: artwork)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(BreezePilotPalette.accent)
                    .frame(width: 96, height: 96)
                    .background(BreezePilotPalette.ice, in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier)

                message
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(messageIdentifier)
            }

            VStack(spacing: 4) {
                if let primaryAction {
                    Button(action: primaryAction.perform) {
                        Label(primaryAction.title, systemImage: primaryIcon)
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 160, minHeight: 28)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(BreezePilotPalette.action)
                }

                if let secondaryAction {
                    Button(action: secondaryAction.perform) {
                        Text(secondaryAction.title)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BreezePilotPalette.accent)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .padding(24)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}
