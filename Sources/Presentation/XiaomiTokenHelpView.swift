import SwiftUI

struct XiaomiTokenHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let guide = URL(
        string: "https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor#readme"
    )!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introduction

                    step(1, "Open the Xiaomi Cloud Tokens Extractor guide and run the tool on your computer.")
                    step(2, "Choose QR sign-in. Use the account and region where the AC appears in Xiaomi Home.")
                    step(3, "Find the AC by name or IP address. Copy its Token and paste it into Add AC.")

                    Link(destination: Self.guide) {
                        Label("Open token extractor guide", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)

                    Text("Keep the token private. This app stores it in your iPhone’s Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Find your device token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var introduction: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            BreezeIllustration(artwork: .xiaomiToken)
            Text("The 32-character device token lets this app talk to your AC over home Wi-Fi.")
        }
    }

    private func step(_ number: Int, _ instruction: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .fontWeight(.semibold)
            Text(instruction)
        }
        .accessibilityElement(children: .combine)
    }
}
