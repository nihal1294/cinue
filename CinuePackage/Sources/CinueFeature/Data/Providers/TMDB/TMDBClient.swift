import Foundation

struct TMDBClient: MetadataProvider {
    let providerID: MetadataProviderID = .tmdb

    private static let metadataSession: URLSession = .shared
    private var apiKey: @Sendable () throws -> String?
    private var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var languageCode: @Sendable () -> String

    init(
        apiKey: @escaping @Sendable () throws -> String?,
        languageCode: @escaping @Sendable () -> String = { CinuePreferences.tmdbLanguageCode },
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await TMDBClient.metadataSession.data(for: request)
        }
    ) {
        self.apiKey = apiKey
        self.languageCode = languageCode
        self.transport = transport
    }

    func search(query: String) async throws -> [MediaSummary] {
        try await performRequest(makeRequest: { credential in
            try makeSearchRequest(query: query, credential: credential)
        }, fallbackKind: nil)
    }

    func browse(category: DiscoverCategory) async throws -> [MediaSummary] {
        try await performRequest(makeRequest: { credential in
            try makeBrowseRequest(category: category, credential: credential)
        }, fallbackKind: category.fallbackKind)
    }

    func details(kind: MediaKind, tmdbID: Int) async throws -> RefreshedMediaDetails {
        let (data, _) = try await performDataRequest { credential in
            try makeDetailsRequest(kind: kind, tmdbID: tmdbID, credential: credential)
        }

        do {
            switch kind {
            case .show:
                let decoded = try JSONDecoder().decode(TMDBTVDetailsResponse.self, from: data)
                return Self.mapTVDetails(decoded, rawJSON: data)
            case .movie:
                let decoded = try JSONDecoder().decode(TMDBMovieDetailsResponse.self, from: data)
                return Self.mapMovieDetails(decoded, rawJSON: data)
            }
        } catch {
            throw MetadataProviderError.invalidResponse
        }
    }

    private func performRequest(
        makeRequest: (TMDBCredential) throws -> URLRequest,
        fallbackKind: MediaKind?
    ) async throws -> [MediaSummary] {
        let (data, _) = try await performDataRequest(makeRequest)
        do {
            let decoded = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
            return decoded.results.compactMap { Self.map($0, fallbackKind: fallbackKind) }
        } catch {
            throw MetadataProviderError.invalidResponse
        }
    }

    private func performDataRequest(
        _ makeRequest: (TMDBCredential) throws -> URLRequest
    ) async throws -> (Data, URLResponse) {
        guard let rawToken = try apiKey(),
              let credential = TMDBCredential(rawValue: rawToken)
        else {
            throw MetadataProviderError.missingAPIKey
        }

        let request = try makeRequest(credential)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as MetadataProviderError {
            throw error
        } catch {
            throw MetadataProviderError.providerUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw MetadataProviderError.invalidResponse
        }

        if http.statusCode == 429 {
            throw MetadataProviderError.rateLimited
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw MetadataProviderError.invalidCredential
        }

        guard (200..<300).contains(http.statusCode) else {
            throw MetadataProviderError.providerUnavailable
        }

        return (data, response)
    }

    static func map(_ result: TMDBSearchResult, fallbackKind: MediaKind? = nil) -> MediaSummary? {
        let kind: MediaKind
        switch result.mediaType {
        case "movie":
            kind = .movie
        case "tv":
            kind = .show
        default:
            guard let fallbackKind else {
                return nil
            }
            kind = fallbackKind
        }

        guard let title = preferredTitle(for: result, kind: kind), title.isEmpty == false else {
            return nil
        }

        return MediaSummary(
            contentIDs: ContentIDs(tmdbID: result.id),
            kind: kind,
            title: title,
            originalTitle: preferredOriginalTitle(for: result, kind: kind),
            overview: result.overview,
            releaseDate: parseDate(result.releaseDate ?? result.firstAirDate),
            posterURL: imageURL(path: result.posterPath, size: .poster),
            backdropURL: imageURL(path: result.backdropPath, size: .backdrop),
            attribution: .tmdb
        )
    }

    private func makeSearchRequest(query: String, credential: TMDBCredential) throws -> URLRequest {
        var components = URLComponents(string: "https://api.themoviedb.org/3/search/multi")
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: languageCode()),
            URLQueryItem(name: "page", value: "1")
        ]

        if case let .apiKey(apiKey) = credential {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MetadataProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        if case let .bearerToken(token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeBrowseRequest(category: DiscoverCategory, credential: TMDBCredential) throws -> URLRequest {
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(category.tmdbPath)")
        var queryItems = [
            URLQueryItem(name: "language", value: languageCode()),
            URLQueryItem(name: "page", value: "1")
        ]

        if case let .apiKey(apiKey) = credential {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MetadataProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        if case let .bearerToken(token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeDetailsRequest(kind: MediaKind, tmdbID: Int, credential: TMDBCredential) throws -> URLRequest {
        let path = kind == .show ? "tv" : "movie"
        var components = URLComponents(string: "https://api.themoviedb.org/3/\(path)/\(tmdbID)")
        var queryItems = [
            URLQueryItem(name: "language", value: languageCode()),
            URLQueryItem(name: "append_to_response", value: "credits,videos,similar")
        ]

        if case let .apiKey(apiKey) = credential {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MetadataProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        if case let .bearerToken(token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func mapTVDetails(_ result: TMDBTVDetailsResponse, rawJSON: Data) -> RefreshedMediaDetails {
        let episodes = [result.lastEpisodeToAir, result.nextEpisodeToAir]
            .compactMap { $0 }
            .reduce(into: [String: RefreshedEpisodeDetails]()) { mapped, episode in
                guard let refreshed = mapEpisodeDetails(episode, showTMDBID: result.id) else {
                    return
                }
                mapped["\(refreshed.seasonNumber)x\(refreshed.episodeNumber)"] = refreshed
            }
            .values
            .sorted {
                ($0.airDate ?? .distantPast, $0.seasonNumber, $0.episodeNumber)
                    < (($1.airDate ?? .distantPast), $1.seasonNumber, $1.episodeNumber)
            }

        return RefreshedMediaDetails(
            contentIDs: ContentIDs(tmdbID: result.id),
            kind: .show,
            title: result.name ?? "Untitled Show",
            overview: result.overview,
            releaseDate: parseDate(result.firstAirDate),
            posterURL: imageURL(path: result.posterPath, size: .poster),
            backdropURL: imageURL(path: result.backdropPath, size: .backdrop),
            providerStatus: result.status,
            normalizedProviderStatus: ProviderStatusNormalizer.normalized(result.status),
            attribution: .tmdb,
            sourceURLString: "https://www.themoviedb.org/tv/\(result.id)",
            rawJSON: rawJSON,
            episodes: episodes
        )
    }

    private static func mapMovieDetails(_ result: TMDBMovieDetailsResponse, rawJSON: Data) -> RefreshedMediaDetails {
        RefreshedMediaDetails(
            contentIDs: ContentIDs(tmdbID: result.id),
            kind: .movie,
            title: result.title ?? "Untitled Movie",
            overview: result.overview,
            releaseDate: parseDate(result.releaseDate),
            posterURL: imageURL(path: result.posterPath, size: .poster),
            backdropURL: imageURL(path: result.backdropPath, size: .backdrop),
            providerStatus: nil,
            normalizedProviderStatus: nil,
            attribution: .tmdb,
            sourceURLString: "https://www.themoviedb.org/movie/\(result.id)",
            rawJSON: rawJSON,
            episodes: []
        )
    }

    private static func mapEpisodeDetails(_ result: TMDBEpisodeDetailsResponse, showTMDBID: Int) -> RefreshedEpisodeDetails? {
        guard let seasonNumber = result.seasonNumber,
              let episodeNumber = result.episodeNumber
        else {
            return nil
        }

        return RefreshedEpisodeDetails(
            tmdbID: result.id,
            title: result.name ?? "\(seasonNumber)x\(String(format: "%02d", episodeNumber))",
            overview: result.overview,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            airDate: parseDate(result.airDate),
            imageURL: imageURL(path: result.stillPath, size: .backdrop),
            sourceURLString: "https://www.themoviedb.org/tv/\(showTMDBID)/season/\(seasonNumber)/episode/\(episodeNumber)",
            rawJSON: try? JSONEncoder().encode(result)
        )
    }

    private static func preferredTitle(for result: TMDBSearchResult, kind: MediaKind) -> String? {
        switch kind {
        case .movie:
            result.title
        case .show:
            result.name
        }
    }

    private static func preferredOriginalTitle(for result: TMDBSearchResult, kind: MediaKind) -> String? {
        switch kind {
        case .movie:
            result.originalTitle
        case .show:
            result.originalName
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func imageURL(path: String?, size: TMDBArtworkSize) -> URL? {
        TMDBArtworkURL.make(path: path, size: size)
    }
}

private extension DiscoverCategory {
    var tmdbPath: String {
        switch self {
        case .trending:
            return "trending/all/week"
        case .popularShows:
            return "tv/popular"
        case .popularMovies:
            return "movie/popular"
        case .upcomingMovies:
            return "movie/upcoming"
        }
    }

    var fallbackKind: MediaKind? {
        switch self {
        case .trending:
            return nil
        case .popularShows:
            return .show
        case .popularMovies, .upcomingMovies:
            return .movie
        }
    }
}

private enum TMDBCredential: Equatable {
    case apiKey(String)
    case bearerToken(String)

    init?(rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return nil
        }

        if value.localizedCaseInsensitiveCompare("bearer") == .orderedSame {
            return nil
        }

        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else {
                return nil
            }
            self = .bearerToken(value)
            return
        }

        if value.hasPrefix("eyJ") || value.contains(".") {
            self = .bearerToken(value)
        } else {
            self = .apiKey(value)
        }
    }
}
