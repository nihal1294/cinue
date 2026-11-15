import Foundation
import SwiftUI

struct AboutCinueView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

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

                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }

            Section("Distribution") {
                Text("Cinue can be built from source for iPhone and iPad. A downloadable iOS Simulator app is also available for Apple Silicon Macs with Xcode. Cinue is not currently available on the App Store.")
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
