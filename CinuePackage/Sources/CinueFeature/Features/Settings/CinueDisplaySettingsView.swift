import SwiftUI

struct CinueDisplaySettingsView: View {
    @AppStorage(CinuePreferenceKeys.appearanceMode) private var appearanceModeRaw = CinueAppearanceMode.system.rawValue
    @AppStorage(CinuePreferenceKeys.hideEpisodeSpoilers) private var hideEpisodeSpoilers = false
    @AppStorage(CinuePreferenceKeys.useExactDates) private var useExactDates = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $appearanceModeRaw) {
                    ForEach(CinueAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("AppearanceModePicker")

                Text("System follows the iPhone or iPad appearance. Light and Dark keep Cinue in that mode until changed.")
                    .foregroundStyle(.secondary)
            }

            Section("Episodes") {
                Toggle("Hide Episode Spoilers", isOn: $hideEpisodeSpoilers)

                Text("Unwatched episode titles and summaries are hidden until you mark the episode watched.")
                    .foregroundStyle(.secondary)
            }

            Section("Dates") {
                Toggle("Use Exact Dates", isOn: $useExactDates)

                Text("Episode release dates use the full local date format when exact dates are enabled.")
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Display")
    }
}

#Preview {
    NavigationStack { CinueDisplaySettingsView() }
}
