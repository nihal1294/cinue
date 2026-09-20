import Observation

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .now
    var nowPath: [Route] = []
    var libraryPath: [Route] = []
    var discoverPath: [Route] = []
    var listsPath: [Route] = []
    var settingsPath: [Route] = []

    func selectTab(_ tab: AppTab) {
        selectedTab = tab
        resetPath(for: tab)
    }

    func resetCurrentTabPath() {
        resetPath(for: selectedTab)
    }

    func resetPath(for tab: AppTab) {
        switch tab {
        case .now:
            nowPath = []
        case .library:
            libraryPath = []
        case .discover:
            discoverPath = []
        case .lists:
            listsPath = []
        case .settings:
            settingsPath = []
        }
    }
}

enum Route: Hashable {
    case showDetail(String)
    case movieDetail(String)
    case episodeDetail(showID: String, season: Int, episode: Int)
    case statistics
    case syncSettings
    case importExport
    case displaySettings
    case notificationSettings
    case privacySettings
    case providerSettings
    case attribution
    case diagnostics
    case about
}
