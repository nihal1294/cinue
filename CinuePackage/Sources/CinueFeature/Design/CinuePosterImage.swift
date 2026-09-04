import SwiftUI

struct CinuePosterImage: View {
    @Environment(\.colorScheme) private var colorScheme

    let url: URL?
    let kind: MediaKind
    var width: CGFloat = 72
    var height: CGFloat = 108
    var cornerRadius: CGFloat = CinueRadius.sm

    var body: some View {
        ZStack {
            CinueRemoteArtworkImage(
                url: url,
                pointSize: CGSize(width: width, height: height)
            ) { phase in
                switch phase {
                case let .success(image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .loading where url != nil:
                    ProgressView()
                        .tint(CinueColors.accentBlue)
                default:
                    fallback
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: fallbackColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: kind == .movie ? "film.fill" : "tv.fill")
                .font(.system(size: min(width, height) * 0.36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CinueColors.accentBlue)
        }
    }

    private var fallbackColors: [Color] {
        colorScheme == .dark
            ? [CinueColors.graphiteElevated, CinueColors.graphiteSurface]
            : [.white, CinueColors.lightBlueTint]
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : CinueColors.accentBlue.opacity(0.12)
    }
}
