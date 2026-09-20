import Foundation

enum MetadataProviderID: String, Sendable, Codable, CaseIterable {
    case theTVDB
    case tmdb
    case tvmaze
}

struct ProviderAttribution: Hashable, Sendable, Codable {
    var providerID: MetadataProviderID
    var providerName: String
    var requiredText: String
    var sourceURL: URL?

    static let theTVDB = ProviderAttribution(
        providerID: .theTVDB,
        providerName: "TheTVDB",
        requiredText: "Metadata and artwork provided by TheTVDB.",
        sourceURL: URL(string: "https://thetvdb.com/")
    )

    static let tmdb = ProviderAttribution(
        providerID: .tmdb,
        providerName: "TMDB",
        requiredText: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
        sourceURL: URL(string: "https://www.themoviedb.org/")
    )

    static let tvmaze = ProviderAttribution(
        providerID: .tvmaze,
        providerName: "TVmaze",
        requiredText: "Schedule and episode data provided by TVmaze.",
        sourceURL: URL(string: "https://www.tvmaze.com/")
    )
}
