import Foundation

enum WatchStatus: String, Sendable, Codable, CaseIterable {
    case unwatched
    case watching
    case watched
    case skipped
    case collected
}

struct UserWatchState: Hashable, Sendable, Codable {
    var status: WatchStatus
    var watchCount: Int
    var watchedAt: Date?
    var isFavorite: Bool
    var isHidden: Bool
    var userRating: Int?
    var notes: String

    init(
        status: WatchStatus = .unwatched,
        watchCount: Int = 0,
        watchedAt: Date? = nil,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        userRating: Int? = nil,
        notes: String = ""
    ) {
        self.status = status
        self.watchCount = watchCount
        self.watchedAt = watchedAt
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.userRating = userRating
        self.notes = notes
    }
}
