import SwiftUI

enum CinueTabBarMetrics {
    static let usesSingleGlassCapsule = true
    static let usesFloatingIcons = true
    static let usesTintedGlassCapsule = true
    static let selectedStateUsesFloatingHalo = true
    static let selectedStateUsesIconPlate = false
    static let iconPlateWidth: CGFloat = 0
    static let minimumButtonHeight: CGFloat = 55
    static let capsuleCornerRadius: CGFloat = 34
    static let selectedIndicatorHeight: CGFloat = 3
    static let unselectedIconMinimumOpacity = 0.82
    static let scrollContentClearance: CGFloat = 96
}

struct CinueTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @Binding var selectedTab: AppTab

    var body: some View {
        tabBarBody
            .padding(.horizontal, CinueSpacing.lg)
            .padding(.bottom, CinueSpacing.xs)
            .accessibilityIdentifier("CinueTabBar")
    }

    @ViewBuilder
    private var tabBarBody: some View {
        let shape = RoundedRectangle(
            cornerRadius: CinueTabBarMetrics.capsuleCornerRadius,
            style: .continuous
        )

        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: CinueSpacing.md) {
                tabItems
                    .background(tabBarTint, in: shape)
                    .glassEffect(
                        .regular.tint(tabBarTint),
                        in: .rect(cornerRadius: CinueTabBarMetrics.capsuleCornerRadius)
                    )
                    .overlay {
                        shape.stroke(tabBarBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                    }
                    .overlay {
                        CinueGlassReflectionOverlay(
                            cornerRadius: CinueTabBarMetrics.capsuleCornerRadius,
                            opacity: colorScheme == .dark ? 0.18 : 0.26
                        )
                    }
            }
        } else {
            tabItems
                .background(.ultraThinMaterial, in: shape)
                .background(tabBarTint, in: shape)
                .overlay {
                    shape.stroke(tabBarBorder, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(
                        cornerRadius: CinueTabBarMetrics.capsuleCornerRadius,
                        opacity: colorScheme == .dark ? 0.14 : 0.22
                    )
                }
        }
    }

    private var tabItems: some View {
        HStack(spacing: CinueSpacing.xs) {
            ForEach(AppTab.allCases) { tab in
                CinueTabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
        }
        .padding(.horizontal, CinueSpacing.sm)
        .padding(.vertical, CinueSpacing.sm)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private var tabBarTint: Color {
        colorScheme == .dark
            ? .white.opacity(0.08)
            : .white.opacity(0.24)
    }

    private var tabBarBorder: Color {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? .white.opacity(0.30) : CinueColors.lightTextSecondary.opacity(0.30)
        }

        return colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.64)
    }
}

private struct CinueTabBarButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        selectedHalo
                            .frame(width: 48, height: 31)
                    }

                    Image(systemName: tab.systemImage)
                        .font(.system(size: tab == .settings ? 17 : 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(iconColor)
                        .frame(width: 48, height: 31)
                }

                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(labelColor)
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(tabTone.accent.opacity(colorScheme == .dark ? 0.86 : 0.78))
                        .frame(width: 18, height: CinueTabBarMetrics.selectedIndicatorHeight)
                        .offset(y: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, minHeight: CinueTabBarMetrics.minimumButtonHeight)
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("Tab-\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tabTone: CinueIconTone {
        switch tab {
        case .now:
            .primary
        case .library:
            .neutral
        case .discover:
            .metadata
        case .lists:
            .privacy
        case .settings:
            .diagnostics
        }
    }

    private var selectedHalo: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tabTone.accent.opacity(colorScheme == .dark ? 0.34 : 0.24),
                            tabTone.accent.opacity(colorScheme == .dark ? 0.10 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 28
                    )
                )

            Ellipse()
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.24), lineWidth: 0.5)
                .blur(radius: 0.5)
        }
    }

    private var iconColor: Color {
        if isSelected {
            return tabTone.accent
        }

        return colorScheme == .dark
            ? CinueColors.textPrimary.opacity(CinueTabBarMetrics.unselectedIconMinimumOpacity)
            : CinueColors.lightTextPrimary.opacity(0.76)
    }

    private var labelColor: Color {
        if isSelected {
            return tabTone.accent
        }

        return colorScheme == .dark
            ? CinueColors.textPrimary.opacity(0.76)
            : CinueColors.lightTextPrimary.opacity(0.74)
    }
}

#Preview {
    @Previewable @State var selectedTab = AppTab.now

    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            CinueTabBar(selectedTab: $selectedTab)
        }
    }
}
