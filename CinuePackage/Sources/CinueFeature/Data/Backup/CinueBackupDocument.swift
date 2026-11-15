import Foundation

struct CinueBackupDocument: Codable, Equatable, Sendable {
    var app: String
    var schemaVersion: Int
    var exportedAt: Date
    var trackedItems: [CinueBackupTrackedItem]
    var episodeStates: [CinueBackupEpisodeState]
    var lists: [CinueBackupList]
    var listItems: [CinueBackupListItem]
    var preferences: CinueBackupPreferences?

    init(
        app: String = "Cinue",
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        trackedItems: [CinueBackupTrackedItem],
        episodeStates: [CinueBackupEpisodeState] = [],
        lists: [CinueBackupList] = [],
        listItems: [CinueBackupListItem] = [],
        preferences: CinueBackupPreferences? = nil
    ) {
        self.app = app
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.trackedItems = trackedItems
        self.episodeStates = episodeStates
        self.lists = lists
        self.listItems = listItems
        self.preferences = preferences
    }
}

struct CinueBackupTrackedItem: Codable, Equatable, Identifiable, Sendable {
    var id: String { localID }

    var localID: String
    var kindRaw: String
    var title: String
    var sortTitle: String?
    var tvdbID: Int?
    var tmdbID: Int?
    var imdbID: String?
    var statusRaw: String
    var watchCount: Int
    var watchedAt: Date?
    var isCollected: Bool?
    var isFavorite: Bool
    var isHidden: Bool
    var userRating: Int?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var localRuntimeMinutes: Int? = nil
}

struct CinueBackupEpisodeState: Codable, Equatable, Identifiable, Sendable {
    var id: String { localID }

    var localID: String
    var showLocalID: String
    var seasonNumber: Int
    var episodeNumber: Int?
    var title: String?
    var tvdbID: Int?
    var tmdbID: Int?
    var statusRaw: String
    var watchCount: Int
    var watchedAt: Date?
    var isCollected: Bool
    var isSkipped: Bool
    var userRating: Int?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var localAirDate: Date? = nil
}

struct CinueBackupList: Codable, Equatable, Identifiable, Sendable {
    var id: String { localID }

    var localID: String
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

struct CinueBackupListItem: Codable, Equatable, Identifiable, Sendable {
    var id: String { localID }

    var localID: String
    var listLocalID: String
    var itemLocalID: String?
    var externalID: String?
    var kindRaw: String
    var tvdbID: Int?
    var tmdbID: Int?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}

struct CinueBackupPreferences: Codable, Equatable, Sendable {
    var appearanceModeRaw: String?
    var hideEpisodeSpoilers: Bool?
    var useExactDates: Bool?
    var tmdbLanguageCode: String?
    var episodeNotificationsEnabled: Bool?
    var episodeNotificationLeadTimeSeconds: TimeInterval?
}

struct BackupImportSummary: Equatable, Sendable {
    var importedItems: Int
    var updatedItems: Int
    var skippedItems: Int
    var source: String

    var message: String {
        var parts: [String] = []

        if importedItems > 0 {
            parts.append("\(importedItems) imported")
        }

        if updatedItems > 0 {
            parts.append("\(updatedItems) updated")
        }

        if skippedItems > 0 {
            parts.append("\(skippedItems) skipped")
        }

        if parts.isEmpty {
            return "No \(source) items changed."
        }

        return "\(source): " + parts.joined(separator: ", ") + "."
    }
}
