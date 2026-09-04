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
                Text("Cinue is distributed as source for local installation. It is not currently available on the App Store.")
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
