import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Data") {
                NavigationLink(value: Route.statistics) {
                    CinueSettingsRow(title: "Insights", symbol: "chart.bar.xaxis", tone: .primary)
                }

                NavigationLink(value: Route.syncSettings) {
                    CinueSettingsRow(title: "Backup and Sync", symbol: "externaldrive.fill", tone: .cloud)
                }

                NavigationLink(value: Route.importExport) {
                    CinueSettingsRow(title: "Import and Export", symbol: "arrow.down.doc.fill", tone: .importExport)
                }

                NavigationLink(value: Route.privacySettings) {
                    CinueSettingsRow(title: "Privacy", symbol: "lock.shield.fill", tone: .privacy)
                }

                NavigationLink(value: Route.displaySettings) {
                    CinueSettingsRow(title: "Display", symbol: "text.magnifyingglass", tone: .primary)
                }

                NavigationLink(value: Route.notificationSettings) {
                    CinueSettingsRow(title: "Notifications", symbol: "bell.badge.fill", tone: .metadata)
                }
            }

            Section("Metadata") {
                NavigationLink(value: Route.providerSettings) {
                    CinueSettingsRow(title: "Provider Keys", symbol: "key.fill", tone: .metadata)
                }

                NavigationLink(value: Route.attribution) {
                    CinueSettingsRow(title: "Attribution", symbol: "checkmark.seal.fill", tone: .metadata)
                }
            }

            Section("App") {
                NavigationLink(value: Route.diagnostics) {
                    CinueSettingsRow(title: "Diagnostics", symbol: "waveform.path.ecg", tone: .diagnostics)
                }

                NavigationLink(value: Route.about) {
                    CinueSettingsRow(title: "About Cinue", symbol: "bookmark.fill", tone: .primary)
                }
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
