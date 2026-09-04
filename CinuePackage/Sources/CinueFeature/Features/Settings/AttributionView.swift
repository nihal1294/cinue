import SwiftUI

struct AttributionView: View {
    var body: some View {
        Form {
            Section("Metadata") {
                CinueSettingsRow(title: "TMDB", symbol: "film.stack.fill", tone: .metadata)

                Image("TMDBLogo", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180, alignment: .leading)
                    .accessibilityLabel("The Movie Database")

                Text(ProviderAttribution.tmdb.requiredText)
                    .foregroundStyle(.secondary)
            }

            Section("Import Compatibility") {
                CinueSettingsRow(title: "SeriesGuide JSON", symbol: "doc.text.fill", tone: .importExport)

                Text(CinueCopy.Settings.seriesGuideImportCompatibility)
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Attribution")
    }
}

#Preview {
    NavigationStack { AttributionView() }
}
