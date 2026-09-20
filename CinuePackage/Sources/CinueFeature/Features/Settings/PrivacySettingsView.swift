import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section("Your Data") {
                CinueSettingsRow(title: "Local Watch History", symbol: "lock.shield.fill", tone: .privacy)

                Text(CinueCopy.Settings.privacyLocalStorage)
                    .foregroundStyle(.secondary)
            }

            Section("Provider Data") {
                Text("Metadata searches contact the configured provider. Provider keys are stored in this device's Keychain.")
                    .foregroundStyle(.secondary)
            }

            Section("Telemetry") {
                Text("This build does not include third-party analytics or behavior tracking.")
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Privacy")
    }
}

#Preview {
    NavigationStack { PrivacySettingsView() }
}
