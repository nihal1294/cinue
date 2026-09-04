import SwiftUI

struct SyncSettingsView: View {
    var body: some View {
        Form {
            Section("Current Mode") {
                CinueSettingsRow(title: "Manual Backup", symbol: "externaldrive.fill", tone: .cloud)

                Text("This personal build stores your data locally on this device. Use Import and Export to save backups into Files, iCloud Drive, AirDrop, or external storage.")
                    .foregroundStyle(.secondary)
            }

            Section("Auto Sync") {
                LabeledContent("iCloud Auto Sync", value: "Not Active")
                LabeledContent("Reason", value: CinueCopy.Settings.iCloudUnavailableReason)

                Text(CinueCopy.Settings.iCloudExplanation)
                    .foregroundStyle(.secondary)
            }

            Section("Phone Change") {
                Text("Before wiping or replacing a phone, export a Cinue backup and store it somewhere outside the app sandbox. On the new device, install Cinue and import that JSON file.")
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Backup and Sync")
    }
}

#Preview {
    NavigationStack { SyncSettingsView() }
}
