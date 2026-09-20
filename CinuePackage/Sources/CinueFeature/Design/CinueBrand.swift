import SwiftUI

enum CinueScreenHeaderMetrics {
    static let canopyHeight: CGFloat = 176
    static let compactBottomSpacing: CGFloat = -56
    static let regularBottomSpacing: CGFloat = -28
}

struct CinueBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 82
    var symbol: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(plateGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.8)
                }
                .shadow(color: shadowColor, radius: 22, y: 12)

            Image(systemName: "bookmark.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(markGradient)
                .offset(y: -size * 0.02)

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.23, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: -size * 0.05)

            if let symbol {
                symbolBadge(symbol)
                    .offset(x: size * 0.30, y: size * 0.30)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var plateGradient: LinearGradient {
        let colors = colorScheme == .dark
            ? [CinueColors.graphiteElevated, CinueColors.graphiteSurface]
            : [.white, CinueColors.lightBlueTint]

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var markGradient: LinearGradient {
        LinearGradient(
            colors: [CinueColors.accentBlue, CinueColors.brandTeal.opacity(0.68)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.82)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.34) : CinueColors.accentBlue.opacity(0.12)
    }

    private func symbolBadge(_ symbol: String) -> some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? CinueColors.ink : .white)
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 0.6)
                }

            Image(systemName: symbol)
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(CinueColors.accentBlue)
        }
        .frame(width: size * 0.32, height: size * 0.32)
    }
}

struct CinueBrandSignature: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            CinueBrandMark(size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Cinue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Text("Your private watch history.")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(.horizontal, CinueSpacing.md)
        .padding(.vertical, CinueSpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

struct CinueIdentityCanopy: View {
    @Environment(\.colorScheme) private var colorScheme

    var height: CGFloat = 176

    var body: some View {
        GeometryReader { proxy in
            decorativeLayer(in: proxy)
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(bottomRuleColor)
                .frame(height: 0.7)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func decorativeLayer(in proxy: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            canopyGradient

            LinearGradient(
                colors: [.white.opacity(0.16), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(colorScheme == .dark ? .screen : .normal)

            HStack(spacing: 9) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(perforationColor(for: index))
                        .frame(width: 5, height: 20)
                }
            }
            .padding(.leading, CinueSpacing.xl)
            .padding(.top, 74)

            CinueCanopyProgressLine()
                .padding(.leading, 26)
                .padding(.trailing, 104)
                .padding(.top, 103)

            Image(systemName: "bookmark.fill")
                .font(.system(size: 78, weight: .semibold))
                .foregroundStyle(watermarkColor)
                .position(x: watermarkX(in: proxy), y: watermarkY(in: proxy))

            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(watermarkCheckColor)
                .position(x: watermarkCheckX(in: proxy), y: watermarkY(in: proxy) - 6)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private func watermarkX(in proxy: GeometryProxy) -> CGFloat {
        proxy.size.width - 48
    }

    private func watermarkCheckX(in proxy: GeometryProxy) -> CGFloat {
        proxy.size.width - 22
    }

    private func watermarkY(in proxy: GeometryProxy) -> CGFloat {
        proxy.size.height * 0.64
    }

    private var canopyGradient: LinearGradient {
        let colors = colorScheme == .dark
            ? [
                CinueColors.graphiteSurface,
                CinueColors.graphiteElevated,
                CinueColors.deepTeal.opacity(0.66),
                CinueColors.accentBlue.opacity(0.72)
            ]
            : [
                CinueColors.lightBlueTint,
                CinueColors.accentBlue.opacity(0.34),
                CinueColors.brandTeal.opacity(0.30),
                .white
            ]

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var watermarkColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : CinueColors.accentBlue.opacity(0.13)
    }

    private var watermarkCheckColor: Color {
        colorScheme == .dark ? .white.opacity(0.22) : .white.opacity(0.84)
    }

    private var bottomRuleColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : CinueColors.accentBlue.opacity(0.14)
    }

    private func perforationColor(for index: Int) -> Color {
        if index == 0 {
            return CinueColors.accentBlue.opacity(colorScheme == .dark ? 0.90 : 0.58)
        }

        return colorScheme == .dark ? .white.opacity(0.28) : CinueColors.lightTextSecondary.opacity(0.28)
    }
}

private struct CinueCanopyProgressLine: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: 3)

                Capsule()
                    .fill(brandGradient)
                    .frame(width: 154, height: 3)
            }

            ZStack {
                Circle()
                    .fill(nodeFill)
                    .overlay {
                        Circle()
                            .stroke(nodeStrokeColor, lineWidth: 0.8)
                    }

                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
        }
    }

    private var trackColor: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.84)
    }

    private var nodeFill: Color {
        colorScheme == .dark ? CinueColors.accentBlue : CinueColors.accentBlue
    }

    private var nodeStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.24) : .white.opacity(0.92)
    }

    private var brandGradient: LinearGradient {
        LinearGradient(
            colors: [CinueColors.accentBlue, CinueColors.brandTeal.opacity(0.82)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct CinueScreenHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CinueIdentityCanopy(height: canopyHeight)
                .ignoresSafeArea(.container, edges: .top)
                .padding(.bottom, canopyBottomSpacing)

            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(primaryTextColor)
                .padding(.horizontal, CinueSpacing.xl)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canopyHeight: CGFloat {
        CinueScreenHeaderMetrics.canopyHeight
    }

    private var canopyBottomSpacing: CGFloat {
        horizontalSizeClass == .regular
            ? CinueScreenHeaderMetrics.regularBottomSpacing
            : CinueScreenHeaderMetrics.compactBottomSpacing
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }
}

#Preview {
    VStack(spacing: 24) {
        CinueScreenHeader(title: "Now")
        CinueBrandSignature()
        CinueBrandMark(symbol: "play.fill")
    }
    .padding()
}
