import SwiftUI

struct ACEmptyStateView: View {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    let artwork: BreezeIllustration.Artwork
    let title: LocalizedStringKey
    let message: Text
    let primaryAction: Action
    let primaryIcon: String
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
            BreezeIllustration(artwork: artwork)

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
                Button(action: primaryAction.perform) {
                    Label(primaryAction.title, systemImage: primaryIcon)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 160, minHeight: 28)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(BreezePilotPalette.action)

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
