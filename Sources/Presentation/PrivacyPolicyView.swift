import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        Form {
            Section("Data on your iPhone") {
                Text("BreezePilot stores your AC and room names, local addresses, model information, and preferences in the app. iOS manages backups of app data.")
                Text("Xiaomi device tokens are stored in this iPhone’s Keychain. BreezePilot uses them to authenticate directly to the AC.")
            }

            Section("Network connections") {
                Text("BreezePilot uses Local Network access to read your AC’s status and send the controls you select. Daikin control uses unencrypted HTTP over your local network.")
                Text("During Xiaomi setup, BreezePilot fetches public model specifications from miot-spec.org over HTTPS. The service receives ordinary connection information, such as your internet IP address. BreezePilot keeps your device token and AC readings out of these requests.")
                Text("The optional token help link opens GitHub in your browser. BreezePilot uses no advertising, analytics, or tracking.")
            }

            Section("Manage or remove data") {
                Text("Use Remove AC to delete a saved AC and its token. You can edit or delete rooms in Settings.")
                Text("You can turn off Local Network access in iPhone Settings. Turn it back on to resume AC control.")
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
