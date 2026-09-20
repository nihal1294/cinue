import CoreData
import SwiftUI

enum CinueSidebarMetrics {
    static let usesLiquidGlassColumn = true
    static let usesFullHeightMaterialColumn = true
    static let usesInsetRoundedPanel = false
    static let usesGlassNavigationRows = true
    static let selectedRowTintOpacity = 0.08
    static let darkPanelTintOpacity = 0.055
    static let lightPanelTintOpacity = 0.14
    static let darkPanelReflectionOpacity = 0.10
    static let lightPanelReflectionOpacity = 0.18
    static let minimumRowHeight: CGFloat = 44
}

public struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(CinuePreferenceKeys.appearanceMode) private var appearanceModeRaw = CinueAppearanceMode.system.rawValue

    public init() {}

    public var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                CinueSidebarRootView(router: environment.router)
            } else {
                CinueTabRootView(router: environment.router)
            }
        }
        .environment(\.managedObjectContext, environment.persistence.container.viewContext)
        .preferredColorScheme(appearanceMode.preferredColorScheme)
    }

    private var appearanceMode: CinueAppearanceMode {
        CinueAppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }
}

private struct CinueTabRootView: View {
    @Bindable var router: AppRouter

    var body: some View {
        NavigationStack(path: pathBinding(for: router.selectedTab)) {
            content(for: router.selectedTab)
                .withCinueRoutes()
                .cinueNavigationChrome()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CinueTabBar(selectedTab: selectedTabBinding)
        }
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.selectTab($0) }
        )
    }

    private func pathBinding(for tab: AppTab) -> Binding<[Route]> {
        switch tab {
        case .now:
            $router.nowPath
        case .library:
            $router.libraryPath
        case .discover:
            $router.discoverPath
        case .lists:
            $router.listsPath
        case .settings:
            $router.settingsPath
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .now:
            NowView()
        case .library:
            LibraryView()
        case .discover:
            DiscoverView()
        case .lists:
            ListsView()
        case .settings:
            SettingsView()
        }
    }
}

private struct CinueSidebarRootView: View {
    @Bindable var router: AppRouter

    var body: some View {
        NavigationSplitView {
            CinueSidebarMenu(selectedTab: selectedTabBinding)
                .toolbar(.hidden, for: .navigationBar)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
        } detail: {
            NavigationStack(path: pathBinding(for: router.selectedTab)) {
                content(for: router.selectedTab)
                    .withCinueRoutes()
                    .cinueNavigationChrome()
            }
        }
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.selectTab($0) }
        )
    }

    private func pathBinding(for tab: AppTab) -> Binding<[Route]> {
        switch tab {
        case .now:
            $router.nowPath
        case .library:
            $router.libraryPath
        case .discover:
            $router.discoverPath
        case .lists:
            $router.listsPath
        case .settings:
            $router.settingsPath
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .now:
            NowView()
        case .library:
            LibraryView()
        case .discover:
            DiscoverView()
        case .lists:
            ListsView()
        case .settings:
            SettingsView()
        }
    }
}

private extension View {
    func withCinueRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .showDetail(let id):
                ShowDetailView(localID: id)
            case .movieDetail(let id):
                MovieDetailView(localID: id)
            case .episodeDetail(let showID, let season, let episode):
                EpisodeDetailView(showID: showID, season: season, episode: episode)
            case .statistics:
                StatisticsView()
            case .syncSettings:
                SyncSettingsView()
            case .importExport:
                ImportExportView()
            case .displaySettings:
                CinueDisplaySettingsView()
            case .notificationSettings:
                NotificationSettingsView()
            case .privacySettings:
                PrivacySettingsView()
            case .providerSettings:
                ProviderSettingsView()
            case .attribution:
                AttributionView()
            case .diagnostics:
                DiagnosticsView()
            case .about:
                AboutCinueView()
            }
        }
    }
}

private struct CinueSidebarMenu: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack {
            sidebarBackground
                .ignoresSafeArea()

            sidebarContent
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.md) {
            CinueSidebarBrandRow()
                .padding(.horizontal, CinueSpacing.lg)
                .padding(.top, CinueSpacing.lg)

            VStack(spacing: CinueSpacing.xs) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        CinueSidebarNavigationRow(
                            title: tab.title,
                            symbol: tab.systemImage,
                            tone: tab.iconTone,
                            isSelected: selectedTab == tab
                        )
                        .frame(maxWidth: .infinity, minHeight: CinueSidebarMetrics.minimumRowHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, CinueSpacing.lg)

            Spacer(minLength: 0)
        }
        .padding(.bottom, CinueSpacing.xl)
    }

    private var sidebarBackground: some View {
        let colors = colorScheme == .dark
            ? [
                CinueColors.ink.opacity(0.58),
                CinueColors.accentBlue.opacity(0.08),
                CinueColors.brandTeal.opacity(0.05)
            ]
            : [
                CinueColors.lightSurface.opacity(0.50),
                CinueColors.lightBlueTint.opacity(0.56),
                .white.opacity(0.62)
            ]

        return ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct CinueSidebarBrandRow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            CinueSidebarGlyph()

            Text("Cinue")
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, CinueSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cinue")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }
}

private struct CinueSidebarNavigationRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let symbol: String
    let tone: CinueIconTone
    let isSelected: Bool

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            sidebarIcon

            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(textColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CinueSpacing.sm)
        .frame(minHeight: CinueSidebarMetrics.minimumRowHeight)
        .background {
            if isSelected {
                selectedBackground
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var selectedBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let tint = CinueColors.accentBlue.opacity(CinueSidebarMetrics.selectedRowTintOpacity)

        if #available(iOS 26, *) {
            shape
                .fill(tint)
                .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: 14))
                .overlay {
                    shape.stroke(tone.accent.opacity(colorScheme == .dark ? 0.20 : 0.28), lineWidth: 0.7)
                }
        } else {
            shape
                .fill(.ultraThinMaterial)
                .background(tint, in: shape)
                .overlay {
                    shape.stroke(tone.accent.opacity(colorScheme == .dark ? 0.20 : 0.28), lineWidth: 0.7)
                }
        }
    }

    private var sidebarIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconFill)
                .frame(width: 28, height: 28)

            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? tone.accent : secondaryIconColor)
        }
        .accessibilityHidden(true)
    }

    private var iconFill: Color {
        if isSelected {
            return tone.accent.opacity(colorScheme == .dark ? 0.18 : 0.13)
        }

        return colorScheme == .dark ? .white.opacity(0.045) : .white.opacity(0.28)
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
        }

        return colorScheme == .dark ? CinueColors.textSecondary.opacity(0.78) : CinueColors.lightTextSecondary
    }

    private var secondaryIconColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary.opacity(0.76) : CinueColors.lightTextSecondary
    }
}

private struct CinueSidebarGlyph: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            CinueIconTile(symbol: "bookmark.fill", tone: .primary, size: 28)

            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: -1)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

}

#Preview("iPhone") {
    RootView()
        .environment(AppEnvironment.preview())
}

private extension AppTab {
    var iconTone: CinueIconTone {
        switch self {
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
}
