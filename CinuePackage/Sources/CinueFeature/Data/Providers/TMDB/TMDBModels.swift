import Foundation

struct TMDBSearchResponse: Decodable {
    var page: Int
    var results: [TMDBSearchResult]
}

struct TMDBSearchResult: Decodable {
    var id: Int
    var mediaType: String?
    var title: String?
    var name: String?
    var originalTitle: String?
    var originalName: String?
    var overview: String?
    var releaseDate: String?
    var firstAirDate: String?
    var posterPath: String?
    var backdropPath: String?

    init(
        id: Int,
        mediaType: String? = nil,
        title: String? = nil,
        name: String? = nil,
        originalTitle: String? = nil,
        originalName: String? = nil,
        overview: String? = nil,
        releaseDate: String? = nil,
        firstAirDate: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.name = name
        self.originalTitle = originalTitle
        self.originalName = originalName
        self.overview = overview
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        self.posterPath = posterPath
        self.backdropPath = backdropPath
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

struct RefreshedMediaDetails: Equatable {
    var contentIDs: ContentIDs
    var kind: MediaKind
    var title: String
    var overview: String?
    var releaseDate: Date?
    var posterURL: URL?
    var backdropURL: URL?
    var providerStatus: String?
    var normalizedProviderStatus: String?
    var attribution: ProviderAttribution
    var sourceURLString: String?
    var rawJSON: Data
    var episodes: [RefreshedEpisodeDetails]
}

struct RefreshedEpisodeDetails: Equatable, Identifiable {
    var id: String {
        if let tmdbID {
            return "tmdb:\(tmdbID)"
        }

        return "\(seasonNumber)x\(episodeNumber)"
    }

    var tmdbID: Int?
    var title: String
    var overview: String?
    var seasonNumber: Int
    var episodeNumber: Int
    var airDate: Date?
    var imageURL: URL?
    var sourceURLString: String?
    var rawJSON: Data?
}

struct TMDBTVDetailsResponse: Decodable {
    var id: Int
    var name: String?
    var overview: String?
    var firstAirDate: String?
    var posterPath: String?
    var backdropPath: String?
    var status: String?
    var nextEpisodeToAir: TMDBEpisodeDetailsResponse?
    var lastEpisodeToAir: TMDBEpisodeDetailsResponse?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case status
        case nextEpisodeToAir = "next_episode_to_air"
        case lastEpisodeToAir = "last_episode_to_air"
    }
}

struct TMDBMovieDetailsResponse: Decodable {
    var id: Int
    var title: String?
    var overview: String?
    var releaseDate: String?
    var posterPath: String?
    var backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

struct TMDBEpisodeDetailsResponse: Codable, Equatable {
    var id: Int?
    var name: String?
    var overview: String?
    var airDate: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var stillPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case airDate = "air_date"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
    }
}
