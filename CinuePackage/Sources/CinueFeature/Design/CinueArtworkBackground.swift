import SwiftUI

enum CinueArtworkBackgroundMetrics {
    static let usesFullScreenArtwork = true
    static let darkArtworkOpacity = 0.88
    static let lightArtworkOpacity = 0.52
    static let darkTopScrimOpacity = 0.26
    static let darkBottomScrimOpacity = 0.68
    static let lightTopScrimOpacity = 0.24
    static let lightBottomScrimOpacity = 0.72
    static let standardBlurRadius: CGFloat = 12
    static let increasedContrastBlurRadius: CGFloat = 22
}

struct CinueArtworkBackground: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let backdropURL: URL?
    let posterURL: URL?
    let kind: MediaKind
    var fallbackTone: CinueIconTone = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fallbackGradient

                if reduceTransparency == false, let artworkURL {
                    artworkLayer(url: artworkURL, size: proxy.size)
                }

                scrimLayer
                vignetteLayer
                brandWash
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var artworkURL: URL? {
        backdropURL ?? posterURL
    }

    private func artworkLayer(url: URL, size: CGSize) -> some View {
        CinueRemoteArtworkImage(url: url, pointSize: size) { phase in
            switch phase {
            case let .success(image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .scaleEffect(1.04)
                    .blur(radius: blurRadius, opaque: true)
                    .saturation(colorScheme == .dark ? 1.02 : 0.92)
                    .opacity(colorScheme == .dark
                        ? CinueArtworkBackgroundMetrics.darkArtworkOpacity
                        : CinueArtworkBackgroundMetrics.lightArtworkOpacity
                    )
            default:
                Color.clear
            }
        }
    }

    private var fallbackGradient: LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            colors = [
                CinueColors.ink,
                CinueColors.graphiteSurface,
                fallbackTone.accent.opacity(kind == .movie ? 0.20 : 0.16)
            ]
        } else {
            colors = [
                CinueColors.lightSurface,
                CinueColors.lightBlueTint,
                fallbackTone.accent.opacity(0.10)
            ]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var scrimLayer: some View {
        LinearGradient(
            colors: scrimColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var scrimColors: [Color] {
        if colorScheme == .dark {
            return colorSchemeContrast == .increased
                ? [.black.opacity(0.46), CinueColors.ink.opacity(0.82)]
                : [
                    .black.opacity(CinueArtworkBackgroundMetrics.darkTopScrimOpacity),
                    CinueColors.ink.opacity(CinueArtworkBackgroundMetrics.darkBottomScrimOpacity)
                ]
        }

        return colorSchemeContrast == .increased
            ? [.white.opacity(0.44), CinueColors.lightSurface.opacity(0.86)]
            : [
                .white.opacity(CinueArtworkBackgroundMetrics.lightTopScrimOpacity),
                CinueColors.lightSurface.opacity(CinueArtworkBackgroundMetrics.lightBottomScrimOpacity)
            ]
    }

    private var vignetteLayer: RadialGradient {
        RadialGradient(
            colors: [
                .clear,
                colorScheme == .dark ? .black.opacity(0.22) : CinueColors.lightSurface.opacity(0.16)
            ],
            center: .center,
            startRadius: 80,
            endRadius: 620
        )
    }

    private var brandWash: LinearGradient {
        LinearGradient(
            colors: [
                fallbackTone.accent.opacity(colorScheme == .dark ? 0.11 : 0.06),
                .clear,
                CinueColors.deepTeal.opacity(colorScheme == .dark ? 0.08 : 0.03)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    private var blurRadius: CGFloat {
        colorSchemeContrast == .increased
            ? CinueArtworkBackgroundMetrics.increasedContrastBlurRadius
            : CinueArtworkBackgroundMetrics.standardBlurRadius
    }
}
