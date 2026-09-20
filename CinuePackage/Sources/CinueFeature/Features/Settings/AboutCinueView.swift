import SwiftUI

struct AboutCinueView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: CinueSpacing.md) {
                    CinueBrandMark(size: 48)

                    VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                        Text("Cinue")
                            .font(.headline.weight(.semibold))

                        Text("Private watch tracking for shows and movies.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, CinueSpacing.xs)
            }

            Section("Distribution") {
                Text("This build targets personal local installation. Public App Store distribution can be revisited after the app is feature-complete and provider/API compliance is ready.")
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("About Cinue")
    }
}

#Preview {
    NavigationStack { AboutCinueView() }
}
