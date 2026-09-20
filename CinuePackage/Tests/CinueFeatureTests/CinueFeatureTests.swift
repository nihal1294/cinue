import Testing
import SwiftUI
@testable import CinueFeature

@MainActor
@Test func appTabsMatchMVPOrder() async throws {
    #expect(AppTab.allCases.map(\.title) == ["Now", "Library", "Discover", "Lists", "Settings"])
}

@MainActor
@Test func routerDefaultsToNowTab() async throws {
    let router = AppRouter()

    #expect(router.selectedTab == .now)
    #expect(router.nowPath.isEmpty)
    #expect(router.libraryPath.isEmpty)
    #expect(router.discoverPath.isEmpty)
    #expect(router.listsPath.isEmpty)
    #expect(router.settingsPath.isEmpty)
}

@MainActor
@Test func selectingTabResetsThatTabsNavigationPath() async throws {
    let router = AppRouter()
    router.settingsPath = [.importExport]
    router.libraryPath = [.showDetail("seriesguide:show:tvdb:1")]

    router.selectTab(.settings)

    #expect(router.selectedTab == .settings)
    #expect(router.settingsPath.isEmpty)
    #expect(router.libraryPath == [.showDetail("seriesguide:show:tvdb:1")])

    router.selectTab(.library)

    #expect(router.selectedTab == .library)
    #expect(router.libraryPath.isEmpty)
}

@Test func appearanceModeMapsToPreferredColorScheme() {
    #expect(CinueAppearanceMode.system.preferredColorScheme == nil)
    #expect(CinueAppearanceMode.light.preferredColorScheme == .light)
    #expect(CinueAppearanceMode.dark.preferredColorScheme == .dark)
}

@Test func appearanceModeDefaultsToSystemForMissingOrInvalidStoredValue() throws {
    let suiteName = "cinue.appearance.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    #expect(CinueAppearanceMode.stored(in: defaults) == .system)

    defaults.set("neon", forKey: CinuePreferenceKeys.appearanceMode)
    #expect(CinueAppearanceMode.stored(in: defaults) == .system)

    defaults.set(CinueAppearanceMode.dark.rawValue, forKey: CinuePreferenceKeys.appearanceMode)
    #expect(CinueAppearanceMode.stored(in: defaults) == .dark)
}
