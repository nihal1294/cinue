import Foundation

struct SeriesGuideShowBackup: Codable, Equatable {
    var tmdbID: Int?
    var tvdbID: Int?
    var imdbID: String?
    var traktID: Int?
    var title: String?
    var overview: String?
    var poster: String?
    var firstAired: String?
    var status: String?
    var network: String?
    var runtime: Int?
    var favorite: Bool?
    var hidden: Bool?
    var lastWatchedMilliseconds: Int64?
    var userNote: String?
    var ratingUser: Int?
    var seasons: [SeriesGuideSeasonBackup]?

    enum CodingKeys: String, CodingKey {
        case tmdbID = "tmdb_id"
        case tvdbID = "tvdb_id"
        case imdbID = "imdb_id"
        case traktID = "trakt_id"
        case title
        case overview
        case poster
        case firstAired = "first_aired"
        case status
        case network
        case runtime
        case favorite
        case hidden
        case lastWatchedMilliseconds = "last_watched_ms"
        case userNote = "user_note"
        case ratingUser = "rating_user"
        case seasons
    }
}

struct SeriesGuideSeasonBackup: Codable, Equatable {
    var season: Int?
    var tmdbID: String?
    var tvdbID: Int?
    var episodes: [SeriesGuideEpisodeBackup]?

    enum CodingKeys: String, CodingKey {
        case season
        case tmdbID = "tmdb_id"
        case tvdbID = "tvdb_id"
        case episodes
    }
}

struct SeriesGuideEpisodeBackup: Codable, Equatable {
    var tmdbID: Int?
    var tvdbID: Int?
    var episode: Int?
    var title: String?
    var overview: String?
    var image: String?
    var firstAiredMilliseconds: Int64?
    var watched: Bool?
    var plays: Int?
    var skipped: Bool?
    var collected: Bool?

    enum CodingKeys: String, CodingKey {
        case tmdbID = "tmdb_id"
        case tvdbID = "tvdb_id"
        case episode
        case title
        case overview
        case image
        case firstAiredMilliseconds = "first_aired"
        case watched
        case plays
        case skipped
        case collected
    }
}

struct SeriesGuideMovieBackup: Codable, Equatable {
    var tmdbID: Int?
    var imdbID: String?
    var title: String?
    var watched: Bool?
    var plays: Int?
    var inWatchlist: Bool?
    var inCollection: Bool?
    var poster: String?
    var overview: String?
    var releasedMilliseconds: Int64?
    var lastUpdatedMilliseconds: Int64?
    var runtimeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case tmdbID = "tmdb_id"
        case imdbID = "imdb_id"
        case title
        case watched
        case plays
        case inWatchlist = "in_watchlist"
        case inCollection = "in_collection"
        case poster
        case overview
        case releasedMilliseconds = "released_utc_ms"
        case lastUpdatedMilliseconds = "last_updated_ms"
        case runtimeMinutes = "runtime_min"
    }
}

struct SeriesGuideListBackup: Codable, Equatable {
    var listID: String?
    var name: String?
    var order: Int?
    var items: [SeriesGuideListItemBackup]?

    enum CodingKeys: String, CodingKey {
        case listID = "list_id"
        case name
        case order
        case items
    }
}

struct SeriesGuideListItemBackup: Codable, Equatable {
    var externalID: String?
    var listItemID: String?
    var tvdbID: Int?
    var type: String?

    enum CodingKeys: String, CodingKey {
        case externalID = "externalId"
        case listItemID = "list_item_id"
        case tvdbID = "tvdb_id"
        case type
    }
}
