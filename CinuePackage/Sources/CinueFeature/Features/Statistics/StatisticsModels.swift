import CoreData
import Foundation

struct StatisticsSnapshot: Equatable {
    let showsTotal: Int
    let showsWithNextEpisodes: Int
    let continuingShows: Int
    let finishedShows: Int
    let episodesTotal: Int
    let watchedEpisodes: Int
    let watchedEpisodeMinutes: Int
    let moviesTotal: Int
    let watchedMovies: Int
    let watchedMovieMinutes: Int
    let watchlistMovies: Int
    let watchlistMovieMinutes: Int
    let collectionMovies: Int
    let collectionMovieMinutes: Int

    var watchedEpisodeDurationText: String {
        Self.durationText(minutes: watchedEpisodeMinutes)
    }

    var watchedMovieDurationText: String {
        Self.durationText(minutes: watchedMovieMinutes)
    }

    var watchlistMovieDurationText: String {
        Self.durationText(minutes: watchlistMovieMinutes)
    }

    var collectionMovieDurationText: String {
        Self.durationText(minutes: collectionMovieMinutes)
    }

    private static func durationText(minutes: Int) -> String {
        guard minutes > 0 else {
            return "0 minutes"
        }

        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let remainingMinutes = minutes % 60
        var parts: [String] = []

        if days > 0 {
            parts.append(days == 1 ? "1 day" : "\(days) days")
        }

        if hours > 0 {
            parts.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }

        if remainingMinutes > 0 || parts.isEmpty {
            parts.append(remainingMinutes == 1 ? "1 minute" : "\(remainingMinutes) minutes")
        }

        return parts.joined(separator: " ")
    }
}

@MainActor
struct StatisticsSnapshotBuilder {
    let context: NSManagedObjectContext

    func snapshot(asOf: Date = Date()) -> StatisticsSnapshot {
        let trackedItems = fetchTrackedItems()
        let episodes = fetchEpisodeStates()
        let showItems = trackedItems.filter { stringValue($0, forKey: "kindRaw") == MediaKind.show.rawValue }
        let visibleShowLocalIDs = Set(showItems.map { stringValue($0, forKey: "localID") })
        let movieItems = trackedItems.filter { stringValue($0, forKey: "kindRaw") == MediaKind.movie.rawValue }
        let showMetadata = fetchMetadata(kind: .show, items: showItems)
        let movieMetadata = fetchMetadata(kind: .movie, items: movieItems)
        let showBackupByLocalID = showMetadata.reduce(into: [String: SeriesGuideShowBackup]()) { result, pair in
            guard let rawJSON = pair.value.value(forKey: "rawJSON") as? Data,
                  let show = try? Self.decode(SeriesGuideShowBackup.self, from: rawJSON)
            else {
                return
            }

            result[pair.key] = show
        }
        let showRuntimeByLocalID = showBackupByLocalID.reduce(into: [String: Int]()) { result, pair in
            guard
                  let runtime = pair.value.runtime,
                  runtime > 0
            else {
                return
            }

            result[pair.key] = runtime
        }
        let movieBackupByLocalID = movieMetadata.reduce(into: [String: SeriesGuideMovieBackup]()) { result, pair in
            guard let rawJSON = pair.value.value(forKey: "rawJSON") as? Data,
                  let movie = try? Self.decode(SeriesGuideMovieBackup.self, from: rawJSON)
            else {
                return
            }

            result[pair.key] = movie
        }
        let continuingShows = showBackupByLocalID.values.reduce(0) { count, show in
            guard let status = show.status?.localizedLowercase else {
                return count
            }

            return status.contains("continu") ? count + 1 : count
        }
        let episodeStatsByShowID = episodeStatsByShowID(episodes)
        let finishedShows = episodeStatsByShowID.reduce(0) { count, pair in
            guard pair.value.total > 0,
                  pair.value.watched >= pair.value.total,
                  let status = showBackupByLocalID[pair.key]?.status?.localizedLowercase,
                  status == "ended" || status == "canceled"
            else {
                return count
            }

            return count + 1
        }
        let visibleEpisodes = episodes.filter {
            visibleShowLocalIDs.contains(stringValue($0, forKey: "showLocalID"))
        }
        let episodeReleaseDatesByLocalID = episodeReleaseDatesByLocalID(visibleEpisodes)
        let actualShowsWithNextEpisodes = Set(
            visibleEpisodes.compactMap { episode -> String? in
                guard isWatched(episode) == false,
                      isSkipped(episode) == false,
                      EpisodeAvailability.isReleased(
                          airDate: episodeReleaseDatesByLocalID[stringValue(episode, forKey: "localID")],
                          asOf: asOf
                      )
                else {
                    return nil
                }

                return stringValue(episode, forKey: "showLocalID")
            }
        ).count
        let watchedEpisodeMinutes = episodes.reduce(0) { total, episode in
            guard isWatched(episode) else {
                return total
            }

            return total + (showRuntimeByLocalID[stringValue(episode, forKey: "showLocalID")] ?? 0)
        }

        let watchedMovies = movieItems.filter(isWatched)
        let watchlistMovies = movieItems.filter { boolValue($0, forKey: "isFavorite") }
        let collectionMovies = movieItems.filter { item in
            boolValue(item, forKey: "isCollected")
                || movieBackupByLocalID[stringValue(item, forKey: "localID")]?.inCollection == true
        }

        return StatisticsSnapshot(
            showsTotal: showItems.count,
            showsWithNextEpisodes: actualShowsWithNextEpisodes,
            continuingShows: continuingShows,
            finishedShows: finishedShows,
            episodesTotal: episodes.count,
            watchedEpisodes: episodes.filter(isWatched).count,
            watchedEpisodeMinutes: watchedEpisodeMinutes,
            moviesTotal: movieItems.count,
            watchedMovies: watchedMovies.count,
            watchedMovieMinutes: movieRuntimeMinutes(for: watchedMovies, backups: movieBackupByLocalID),
            watchlistMovies: watchlistMovies.count,
            watchlistMovieMinutes: movieRuntimeMinutes(for: watchlistMovies, backups: movieBackupByLocalID),
            collectionMovies: collectionMovies.count,
            collectionMovieMinutes: movieRuntimeMinutes(for: collectionMovies, backups: movieBackupByLocalID)
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func episodeStatsByShowID(_ episodes: [NSManagedObject]) -> [String: EpisodeStats] {
        episodes.reduce(into: [:]) { result, episode in
            let showLocalID = stringValue(episode, forKey: "showLocalID")
            var stats = result[showLocalID] ?? EpisodeStats()
            stats.total += 1
            if isWatched(episode) {
                stats.watched += 1
            } else if isSkipped(episode) {
                stats.skipped += 1
            } else {
                stats.unwatched += 1
            }
            result[showLocalID] = stats
        }
    }

    private func episodeReleaseDatesByLocalID(_ episodes: [NSManagedObject]) -> [String: Date] {
        let localIDs = episodes.map { stringValue($0, forKey: "localID") }
        let cacheIDs = localIDs.flatMap { localID in
            [
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

        guard let metadata = try? context.fetch(request) else {
            return [:]
        }

        let metadataByCacheID = metadata.reduce(into: [String: NSManagedObject]()) { result, record in
            let cacheID = stringValue(record, forKey: "cacheID")
            if cacheID.isEmpty == false {
                result[cacheID] = record
            }
        }

        return localIDs.reduce(into: [:]) { result, localID in
            let preferredCacheIDs = [
                "seriesguide:episode:\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: localID)
            ]
            if let releaseDate = preferredCacheIDs.lazy.compactMap({ cacheID in
                metadataByCacheID[cacheID]?.value(forKey: "releaseDate") as? Date
            }).first {
                result[localID] = releaseDate
            }
        }
    }

    private func movieRuntimeMinutes(
        for movies: [NSManagedObject],
        backups: [String: SeriesGuideMovieBackup]
    ) -> Int {
        movies.reduce(0) { total, movie in
            let localID = stringValue(movie, forKey: "localID")
            return total + max(backups[localID]?.runtimeMinutes ?? 0, 0)
        }
    }

    private func fetchTrackedItems() -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "isHidden == NO")

        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private func fetchEpisodeStates() -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.returnsObjectsAsFaults = false

        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private func fetchMetadata(kind: MediaKind, items: [NSManagedObject]) -> [String: NSManagedObject] {
        let cacheIDsByLocalID = items.reduce(into: [String: [String]]()) { result, item in
            let localID = stringValue(item, forKey: "localID")
            result[localID] = [
                "seriesguide:\(kind.rawValue):\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: kind.rawValue, localID: localID)
            ]
        }
        let cacheIDs = cacheIDsByLocalID.values.flatMap { $0 }

        guard cacheIDs.isEmpty == false else {
            return [:]
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)

        do {
            let metadataByCacheID = try context.fetch(request).reduce(into: [String: NSManagedObject]()) { result, metadata in
                let cacheID = stringValue(metadata, forKey: "cacheID")
                if cacheID.isEmpty == false {
                    result[cacheID] = metadata
                }
            }

            return cacheIDsByLocalID.reduce(into: [String: NSManagedObject]()) { result, pair in
                if let metadata = pair.value.compactMap({ metadataByCacheID[$0] }).first {
                    result[pair.key] = metadata
                }
            }
        } catch {
            return [:]
        }
    }

    private func isWatched(_ object: NSManagedObject) -> Bool {
        stringValue(object, forKey: "statusRaw") == WatchStatus.watched.rawValue
            || intValue(object, forKey: "watchCount") > 0
    }

    private func isSkipped(_ object: NSManagedObject) -> Bool {
        boolValue(object, forKey: "isSkipped")
            || stringValue(object, forKey: "statusRaw") == WatchStatus.skipped.rawValue
    }

    private func stringValue(_ object: NSManagedObject, forKey key: String) -> String {
        object.value(forKey: key) as? String ?? ""
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

}

private struct EpisodeStats {
    var total = 0
    var watched = 0
    var skipped = 0
    var unwatched = 0
}
