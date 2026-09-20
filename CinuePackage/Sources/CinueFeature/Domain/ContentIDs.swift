import Foundation

struct ContentIDs: Hashable, Sendable, Codable {
    var localID: String
    var tvdbID: Int?
    var tmdbID: Int?
    var imdbID: String?
    var traktID: Int?

    init(
        localID: String = UUID().uuidString,
        tvdbID: Int? = nil,
        tmdbID: Int? = nil,
        imdbID: String? = nil,
        traktID: Int? = nil
    ) {
        self.localID = localID
        self.tvdbID = tvdbID
        self.tmdbID = tmdbID
        self.imdbID = imdbID
        self.traktID = traktID
    }
}
