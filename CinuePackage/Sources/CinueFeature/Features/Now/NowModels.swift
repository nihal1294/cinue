import CoreData
import Foundation

struct NowDashboardSnapshot: Equatable {
    let upNext: [NowEpisodeSnapshot]
    let recentlyWatched: [NowEpisodeSnapshot]
    let recentlyAired: [NowEpisodeSnapshot]
    let upcoming: [NowEpisodeSnapshot]

    var isEmpty: Bool {
        upNext.isEmpty && recentlyWatched.isEmpty && recentlyAired.isEmpty && upcoming.isEmpty
    }
}

struct NowEpisodeSnapshot: Equatable, Identifiable {
    let id: String
    let localID: String
    let showLocalID: String
    let showTitle: String
    let showPosterURL: URL?
    let episodeTitle: String?
    let seasonNumber: Int
    let episodeNumber: Int?
    let airDate: Date?
    let watchedAt: Date?
    let isWatched: Bool
    let isCollected: Bool
    let isSkipped: Bool

    var episodeCode: String {
        guard let episodeNumber else {
            return "S\(seasonNumber)"
        }

        return "\(seasonNumber)x\(String(format: "%02d", episodeNumber))"
    }

    var titleLine: String {
        guard let episodeTitle, episodeTitle.isEmpty == false else {
            return episodeCode
        }

        return "\(episodeCode) \(episodeTitle)"
    }

    var stateLabel: String {
        if isWatched {
            return CinueCopy.State.watched
        }

        if isSkipped {
            return CinueCopy.State.skipped
        }

        if isCollected {
            return CinueCopy.State.inCollection
        }

        return CinueCopy.State.unwatched
    }

    var accessibilityLabel: String {
        var parts = [showTitle, titleLine, stateLabel]
            .compactMap { $0.nilIfEmpty }

        if let dateLine = dateLine?.nilIfEmpty {
            parts.append(dateLine)
        }

        return parts.joined(separator: ", ")
    }

    var dateLine: String? {
        if let watchedAt {
            return "Watched \(Self.relativeDateString(for: watchedAt))"
        }

        guard let airDate else {
            return nil
        }

        return Self.airDateString(for: airDate)
    }

    private static func airDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = CinuePreferences.useExactDates ? .full : .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
struct NowSnapshotBuilder {
    let context: NSManagedObjectContext
    var now: () -> Date = Date.init

    func snapshot(
        trackedShows: [NSManagedObject],
        episodeStates: [NSManagedObject]
    ) -> NowDashboardSnapshot {
        let visibleShows = trackedShows.filter { show in
            stringValue(show, forKey: "kindRaw") == MediaKind.show.rawValue
                && boolValue(show, forKey: "isHidden") == false
        }
        let showSnapshotsByLocalID = LibraryItemSnapshotBuilder(context: context)
            .snapshots(from: visibleShows)
            .reduce(into: [:]) { result, snapshot in
                result[snapshot.localID] = snapshot
            }
        let episodeMetadataByCacheID = fetchEpisodeMetadata(for: episodeStates)
        let episodes = episodeStates.compactMap { episode -> NowEpisodeSnapshot? in
            let showLocalID = stringValue(episode, forKey: "showLocalID")
            guard let show = showSnapshotsByLocalID[showLocalID] else {
                return nil
            }

            let localID = stringValue(episode, forKey: "localID")
            let metadata = episodeMetadataByCacheID["seriesguide:episode:\(localID)"]
                ?? episodeMetadataByCacheID[ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: localID)]
            let title = stringValue(episode, forKey: "title").nilIfEmpty
                ?? stringValue(metadata, forKey: "title").nilIfEmpty
            let statusRaw = stringValue(episode, forKey: "statusRaw")
            let watchCount = intValue(episode, forKey: "watchCount")

            return NowEpisodeSnapshot(
                id: localID,
                localID: localID,
                showLocalID: showLocalID,
                showTitle: show.title,
                showPosterURL: show.posterURL,
                episodeTitle: title,
                seasonNumber: intValue(episode, forKey: "seasonNumber"),
                episodeNumber: optionalIntValue(episode, forKey: "episodeNumber"),
                airDate: metadata?.value(forKey: "releaseDate") as? Date,
                watchedAt: episode.value(forKey: "watchedAt") as? Date,
                isWatched: statusRaw == WatchStatus.watched.rawValue || watchCount > 0,
                isCollected: boolValue(episode, forKey: "isCollected") || statusRaw == WatchStatus.collected.rawValue,
                isSkipped: boolValue(episode, forKey: "isSkipped") || statusRaw == WatchStatus.skipped.rawValue
            )
        }

        return NowDashboardSnapshot(
            upNext: upNextEpisodes(from: episodes),
            recentlyWatched: recentlyWatchedEpisodes(from: episodes),
            recentlyAired: recentlyAiredEpisodes(from: episodes),
            upcoming: upcomingEpisodes(from: episodes)
        )
    }

    private func upNextEpisodes(from episodes: [NowEpisodeSnapshot]) -> [NowEpisodeSnapshot] {
        let currentDate = now()

        return Dictionary(grouping: episodes.filter { episode in
            episode.isWatched == false
                && episode.isSkipped == false
                && isReleased(episode, asOf: currentDate)
        }, by: \.showLocalID)
            .compactMap { _, showEpisodes in
                showEpisodes.sorted(by: episodeAscending).first
            }
            .sorted(by: upNextReleaseDescending)
    }

    private func recentlyWatchedEpisodes(from episodes: [NowEpisodeSnapshot]) -> [NowEpisodeSnapshot] {
        episodes
            .filter(\.isWatched)
            .sorted {
                ($0.watchedAt ?? .distantPast, $0.showTitle, $0.seasonNumber, $0.episodeNumber ?? 0)
                    > (($1.watchedAt ?? .distantPast), $1.showTitle, $1.seasonNumber, $1.episodeNumber ?? 0)
            }
            .prefix(40)
            .map { $0 }
    }

    private func recentlyAiredEpisodes(from episodes: [NowEpisodeSnapshot]) -> [NowEpisodeSnapshot] {
        let currentDate = now()

        return episodes
            .filter { episode in
                guard let airDate = episode.airDate else {
                    return false
                }

                return airDate <= currentDate && episode.isWatched == false
            }
            .sorted {
                ($0.airDate ?? .distantPast, $0.showTitle, $0.seasonNumber, $0.episodeNumber ?? 0)
                    > (($1.airDate ?? .distantPast), $1.showTitle, $1.seasonNumber, $1.episodeNumber ?? 0)
            }
            .prefix(40)
            .map { $0 }
    }

    private func upcomingEpisodes(from episodes: [NowEpisodeSnapshot]) -> [NowEpisodeSnapshot] {
        let currentDate = now()

        return episodes
            .filter { episode in
                guard let airDate = episode.airDate else {
                    return false
                }

                return airDate > currentDate && episode.isWatched == false
            }
            .sorted(by: episodeAirDateAscending)
            .prefix(40)
            .map { $0 }
    }

    private func isReleased(_ episode: NowEpisodeSnapshot, asOf currentDate: Date) -> Bool {
        guard let airDate = episode.airDate else {
            return false
        }

        return airDate <= currentDate
    }

    private func episodeAscending(_ lhs: NowEpisodeSnapshot, _ rhs: NowEpisodeSnapshot) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber {
            return lhs.seasonNumber < rhs.seasonNumber
        }

        return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
    }

    private func episodeAirDateAscending(_ lhs: NowEpisodeSnapshot, _ rhs: NowEpisodeSnapshot) -> Bool {
        if lhs.airDate != rhs.airDate {
            return (lhs.airDate ?? .distantFuture) < (rhs.airDate ?? .distantFuture)
        }

        return episodeAscending(lhs, rhs)
    }

    private func upNextReleaseDescending(_ lhs: NowEpisodeSnapshot, _ rhs: NowEpisodeSnapshot) -> Bool {
        switch (lhs.airDate, rhs.airDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            let titleCompare = lhs.showTitle.localizedCaseInsensitiveCompare(rhs.showTitle)
            if titleCompare != .orderedSame {
                return titleCompare == .orderedAscending
            }

            return episodeAscending(lhs, rhs)
        }
    }

    private func fetchEpisodeMetadata(for episodeStates: [NSManagedObject]) -> [String: NSManagedObject] {
        let cacheIDs = episodeStates.flatMap { episode in
            let localID = stringValue(episode, forKey: "localID")
            return [
                "seriesguide:episode:\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: localID)
            ]
        }

        guard cacheIDs.isEmpty == false else {
            return [:]
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)

        do {
            return try context.fetch(request).reduce(into: [:]) { result, metadata in
                let cacheID = stringValue(metadata, forKey: "cacheID")
                if cacheID.isEmpty == false {
                    result[cacheID] = metadata
                }
            }
        } catch {
            return [:]
        }
    }

    private func stringValue(_ object: NSManagedObject?, forKey key: String, fallback: String = "") -> String {
        object?.value(forKey: key) as? String ?? fallback
    }

    private func boolValue(_ object: NSManagedObject, forKey key: String) -> Bool {
        object.value(forKey: key) as? Bool ?? false
    }

    private func intValue(_ object: NSManagedObject, forKey key: String) -> Int {
        if let number = object.value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return object.value(forKey: key) as? Int ?? 0
    }

    private func optionalIntValue(_ object: NSManagedObject, forKey key: String) -> Int? {
        if let number = object.value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return object.value(forKey: key) as? Int
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
