import SwiftUI

struct CinuePlaceholderScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let symbol: String
    let headline: String
    let message: String

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                CinueScreenHeader(title: title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                VStack(spacing: CinueSpacing.xl) {
                    CinueBrandMark(symbol: symbol)

                    VStack(spacing: CinueSpacing.sm) {
                        Text(headline)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .multilineTextAlignment(.center)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(secondaryTextColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 320)
                }

                Spacer()
            }
            .padding(.bottom, CinueSpacing.xxl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(title)Screen")
        .toolbar(.hidden, for: .navigationBar)
        .cinueCinematicNavigationBar(colorScheme: colorScheme)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

#Preview {
    CinuePlaceholderScreen(
        title: "Now",
        symbol: "play.circle",
        headline: "Nothing to Watch Yet",
        message: "Add shows and movies from Discover."
    )
}
