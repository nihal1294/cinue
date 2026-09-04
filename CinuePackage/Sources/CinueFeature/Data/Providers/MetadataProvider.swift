import Foundation

protocol MetadataProvider: Sendable {
    var providerID: MetadataProviderID { get }
    func search(query: String) async throws -> [MediaSummary]
    func browse(category: DiscoverCategory) async throws -> [MediaSummary]
}

enum DiscoverCategory: String, CaseIterable, Identifiable, Sendable {
    case trending
    case popularShows
    case popularMovies
    case upcomingMovies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending:
            return "Trending"
        case .popularShows:
            return "Popular Shows"
        case .popularMovies:
            return "Popular Movies"
        case .upcomingMovies:
            return "Upcoming Movies"
        }
    }

    var symbol: String {
        switch self {
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .popularShows:
            return "tv.fill"
        case .popularMovies:
            return "film.fill"
        case .upcomingMovies:
            return "calendar"
        }
    }
}

enum MetadataProviderError: Error, Equatable {
    case missingAPIKey
    case invalidCredential
    case invalidResponse
    case rateLimited
    case providerUnavailable
}
