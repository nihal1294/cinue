import SwiftUI

enum CinueGlassMetrics {
    static let minimumTouchTarget: CGFloat = 44
    static let detailActionMinHeight: CGFloat = 48
}

enum CinueGlassSurfaceMetrics {
    static let contentSurfacesUseNativeLiquidGlass = true
    static let darkSurfaceTintOpacity = 0.09
    static let darkElevatedSurfaceTintOpacity = 0.11
    static let darkQuietSurfaceTintOpacity = 0.07
    static let lightSurfaceTintOpacity = 0.14
    static let lightElevatedSurfaceTintOpacity = 0.18
    static let lightQuietSurfaceTintOpacity = 0.10
    static let darkReflectionOpacity = 0.14
    static let lightReflectionOpacity = 0.24
}

struct CinueGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = CinueRadius.lg
    var interactive = false

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

enum CinueSurfaceProminence {
    case quiet
    case standard
    case elevated
}

struct CinueContentSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = CinueRadius.lg
    var prominence: CinueSurfaceProminence = .standard

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(reducedTransparencyFill, in: shape)
                .overlay {
                    shape.stroke(surfaceBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                }
        } else if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(surfaceTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(surfaceBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(surfaceTint, in: shape)
                .overlay {
                    shape.stroke(surfaceBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
                }
        }
    }

    private var surfaceTint: Color {
        switch prominence {
        case .quiet:
            colorScheme == .dark
                ? .white.opacity(CinueGlassSurfaceMetrics.darkQuietSurfaceTintOpacity)
                : .white.opacity(CinueGlassSurfaceMetrics.lightQuietSurfaceTintOpacity)
        case .standard:
            colorScheme == .dark
                ? .white.opacity(CinueGlassSurfaceMetrics.darkSurfaceTintOpacity)
                : .white.opacity(CinueGlassSurfaceMetrics.lightSurfaceTintOpacity)
        case .elevated:
            colorScheme == .dark
                ? .white.opacity(CinueGlassSurfaceMetrics.darkElevatedSurfaceTintOpacity)
                : .white.opacity(CinueGlassSurfaceMetrics.lightElevatedSurfaceTintOpacity)
        }
    }

    private var reducedTransparencyFill: Color {
        switch prominence {
        case .quiet:
            colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.68) : .white.opacity(0.84)
        case .standard:
            colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.74) : .white.opacity(0.92)
        case .elevated:
            colorScheme == .dark ? CinueColors.graphiteSurface.opacity(0.82) : .white.opacity(0.96)
        }
    }

    private var surfaceBorder: Color {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? .white.opacity(0.30) : CinueColors.lightTextSecondary.opacity(0.28)
        }

        return colorScheme == .dark ? .white.opacity(0.12) : CinueColors.accentBlue.opacity(0.13)
    }

    private var reflectionOpacity: Double {
        colorScheme == .dark
            ? CinueGlassSurfaceMetrics.darkReflectionOpacity
            : CinueGlassSurfaceMetrics.lightReflectionOpacity
    }
}

struct CinueGlassControlModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var cornerRadius: CGFloat = CinueRadius.lg
    var tone: CinueIconTone = .primary
    var interactive = true
    var isSelected = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26, *) {
            content
                .background(controlBaseFill, in: shape)
                .glassEffect(
                    interactive ? .regular.tint(controlGlassTint).interactive() : .regular.tint(controlGlassTint),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    shape.stroke(controlBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(controlBaseFill, in: shape)
                .overlay {
                    shape.stroke(controlBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
                }
        }
    }

    private var controlBaseFill: Color {
        if isSelected {
            return tone.accent.opacity(colorScheme == .dark ? 0.07 : 0.09)
        }

        return colorScheme == .dark
            ? .white.opacity(0.035)
            : .white.opacity(0.38)
    }

    private var controlGlassTint: Color {
        guard isSelected else {
            return colorScheme == .dark
                ? .white.opacity(0.055)
                : CinueColors.lightBlueTint.opacity(0.22)
        }

        return tone.accent.opacity(colorScheme == .dark ? 0.11 : 0.10)
    }

    private var controlBorder: Color {
        if isSelected {
            return tone.accent.opacity(colorScheme == .dark ? 0.42 : 0.34)
        }

        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? .white.opacity(0.28) : CinueColors.lightTextSecondary.opacity(0.24)
        }

        return colorScheme == .dark
            ? .white.opacity(0.15)
            : CinueColors.lightTextPrimary.opacity(0.11)
    }

    private var reflectionOpacity: Double {
        let base = colorScheme == .dark ? CinueGlassSurfaceMetrics.darkReflectionOpacity : 0.13
        return isSelected ? base * 1.15 : base
    }
}

struct CinuePillCountBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let count: Int
    let isSelected: Bool

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badgeFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(badgeBorder, lineWidth: 0.5)
            }
    }

    private var badgeFill: Color {
        if isSelected {
            return colorScheme == .dark
                ? .white.opacity(0.18)
                : CinueColors.accentBlue.opacity(0.13)
        }

        return colorScheme == .dark
            ? CinueColors.accentBlue.opacity(0.18)
            : CinueColors.lightTextPrimary.opacity(0.055)
    }

    private var badgeBorder: Color {
        if isSelected {
            return colorScheme == .dark
                ? .white.opacity(0.14)
                : CinueColors.accentBlue.opacity(0.16)
        }

        return colorScheme == .dark
            ? .white.opacity(0.08)
            : CinueColors.lightTextPrimary.opacity(0.07)
    }
}

struct CinueCompactGlassControlModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var cornerRadius: CGFloat = CinueRadius.lg
    var tone: CinueIconTone = .primary
    var isSelected = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(compactFill, in: shape)
            .overlay {
                shape.stroke(compactBorder, lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.65)
            }
            .overlay {
                CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
            }
    }

    private var compactFill: Color {
        if isSelected {
            return tone.accent.opacity(colorScheme == .dark ? 0.18 : 0.13)
        }

        return colorScheme == .dark
            ? .white.opacity(0.08)
            : .white.opacity(0.72)
    }

    private var compactBorder: Color {
        if isSelected {
            return tone.accent.opacity(colorScheme == .dark ? 0.42 : 0.12)
        }

        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? .white.opacity(0.28) : CinueColors.lightTextSecondary.opacity(0.24)
        }

        return colorScheme == .dark
            ? .white.opacity(0.14)
            : .clear
    }

    private var reflectionOpacity: Double {
        colorScheme == .dark ? 0.10 : 0.11
    }
}

struct CinueGlassReflectionOverlay: View {
    let cornerRadius: CGFloat
    let opacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(opacity),
                        .white.opacity(opacity * 0.30),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

extension View {
    func cinueGlass(cornerRadius: CGFloat = CinueRadius.lg, interactive: Bool = false) -> some View {
        modifier(CinueGlassBackground(cornerRadius: cornerRadius, interactive: interactive))
    }

    func cinueContentSurface(
        cornerRadius: CGFloat = CinueRadius.lg,
        prominence: CinueSurfaceProminence = .standard
    ) -> some View {
        modifier(CinueContentSurfaceModifier(cornerRadius: cornerRadius, prominence: prominence))
    }

    func cinueGlassControl(
        cornerRadius: CGFloat = CinueRadius.lg,
        tone: CinueIconTone = .primary,
        interactive: Bool = true,
        isSelected: Bool = false
    ) -> some View {
        modifier(
            CinueGlassControlModifier(
                cornerRadius: cornerRadius,
                tone: tone,
                interactive: interactive,
                isSelected: isSelected
            )
        )
    }

    func cinueCompactGlassControl(
        cornerRadius: CGFloat = CinueRadius.lg,
        tone: CinueIconTone = .primary,
        isSelected: Bool = false
    ) -> some View {
        modifier(
            CinueCompactGlassControlModifier(
                cornerRadius: cornerRadius,
                tone: tone,
                isSelected: isSelected
            )
        )
    }

    func cinueBottomChromeScrollMargins() -> some View {
        contentMargins(.bottom, CinueTabBarMetrics.scrollContentClearance, for: .scrollContent)
    }

    func cinueNavigationChrome() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .tint(CinueColors.accentBlue)
    }

    func cinueCinematicNavigationBar(colorScheme: ColorScheme) -> some View {
        let background = colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface

        return toolbarBackground(background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
    }
}
