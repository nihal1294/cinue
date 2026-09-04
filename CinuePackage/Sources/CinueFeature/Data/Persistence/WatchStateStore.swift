import CoreData
import Foundation

@MainActor
struct WatchStateStore {
    private let context: NSManagedObjectContext
    private let now: () -> Date

    init(context: NSManagedObjectContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    func markEpisodeWatched(localID: String) throws {
        let episode = try episodeState(localID: localID)
        let timestamp = now()
        let existingWatchCount = intValue(episode, forKey: "watchCount")

        episode.setValue(WatchStatus.watched.rawValue, forKey: "statusRaw")
        episode.setValue(Int32(max(existingWatchCount, 1)), forKey: "watchCount")
        episode.setValue(timestamp, forKey: "watchedAt")
        episode.setValue(false, forKey: "isSkipped")
        episode.setValue(timestamp, forKey: "updatedAt")

        try updateShowProgress(showLocalID: stringValue(episode, forKey: "showLocalID"), timestamp: timestamp)
        try saveIfNeeded()
    }

    func watchEpisodeAgain(localID: String) throws {
        let episode = try episodeState(localID: localID)
        let timestamp = now()
        let existingWatchCount = intValue(episode, forKey: "watchCount")

        episode.setValue(WatchStatus.watched.rawValue, forKey: "statusRaw")
        episode.setValue(Int32(clamping: existingWatchCount + 1), forKey: "watchCount")
        episode.setValue(timestamp, forKey: "watchedAt")
        episode.setValue(false, forKey: "isSkipped")
        episode.setValue(timestamp, forKey: "updatedAt")

        try updateShowProgress(showLocalID: stringValue(episode, forKey: "showLocalID"), timestamp: timestamp)
        try saveIfNeeded()
    }

    func markEpisodeUnwatched(localID: String) throws {
        let episode = try episodeState(localID: localID)
        let timestamp = now()

        episode.setValue(WatchStatus.unwatched.rawValue, forKey: "statusRaw")
        episode.setValue(Int32(0), forKey: "watchCount")
        episode.setValue(nil, forKey: "watchedAt")
        episode.setValue(false, forKey: "isSkipped")
        episode.setValue(timestamp, forKey: "updatedAt")

        try updateShowProgress(showLocalID: stringValue(episode, forKey: "showLocalID"), timestamp: timestamp)
        try saveIfNeeded()
    }

    func markEpisodesWatchedUpTo(showLocalID: String, season: Int, episode: Int) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.returnsObjectsAsFaults = false
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "showLocalID == %@", showLocalID),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "seasonNumber < %@", NSNumber(value: season)),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "seasonNumber == %@", NSNumber(value: season)),
                    NSPredicate(format: "episodeNumber <= %@", NSNumber(value: episode))
                ])
            ])
        ])

        let timestamp = now()
        for episodeState in try context.fetch(request) {
            episodeState.setValue(WatchStatus.watched.rawValue, forKey: "statusRaw")
            episodeState.setValue(Int32(max(intValue(episodeState, forKey: "watchCount"), 1)), forKey: "watchCount")
            episodeState.setValue(timestamp, forKey: "watchedAt")
            episodeState.setValue(false, forKey: "isSkipped")
            episodeState.setValue(timestamp, forKey: "updatedAt")
        }

        try updateShowProgress(showLocalID: showLocalID, timestamp: timestamp)
        try saveIfNeeded()
    }

    func setSeasonWatched(showLocalID: String, season: Int, isWatched: Bool) throws {
        let timestamp = now()
        for episode in try episodes(showLocalID: showLocalID, season: season) {
            episode.setValue(isWatched ? WatchStatus.watched.rawValue : WatchStatus.unwatched.rawValue, forKey: "statusRaw")
            episode.setValue(Int32(isWatched ? max(intValue(episode, forKey: "watchCount"), 1) : 0), forKey: "watchCount")
            episode.setValue(isWatched ? timestamp : nil, forKey: "watchedAt")
            episode.setValue(false, forKey: "isSkipped")
            episode.setValue(timestamp, forKey: "updatedAt")
        }

        try updateShowProgress(showLocalID: showLocalID, timestamp: timestamp)
        try saveIfNeeded()
    }

    func setSeasonCollected(showLocalID: String, season: Int, isCollected: Bool) throws {
        let timestamp = now()
        for episode in try episodes(showLocalID: showLocalID, season: season) {
            episode.setValue(isCollected, forKey: "isCollected")
            episode.setValue(timestamp, forKey: "updatedAt")
        }

        try saveIfNeeded()
    }

    func setSeasonSkipped(showLocalID: String, season: Int, isSkipped: Bool) throws {
        let timestamp = now()
        for episode in try episodes(showLocalID: showLocalID, season: season) {
            episode.setValue(isSkipped, forKey: "isSkipped")
            if isSkipped {
                episode.setValue(WatchStatus.skipped.rawValue, forKey: "statusRaw")
                episode.setValue(Int32(0), forKey: "watchCount")
                episode.setValue(nil, forKey: "watchedAt")
            } else if stringValue(episode, forKey: "statusRaw") == WatchStatus.skipped.rawValue {
                episode.setValue(WatchStatus.unwatched.rawValue, forKey: "statusRaw")
            }
            episode.setValue(timestamp, forKey: "updatedAt")
        }

        try updateShowProgress(showLocalID: showLocalID, timestamp: timestamp)
        try saveIfNeeded()
    }

    func setShowWatched(showLocalID: String, isWatched: Bool) throws {
        let timestamp = now()
        for episode in try episodes(showLocalID: showLocalID, season: nil) {
            episode.setValue(isWatched ? WatchStatus.watched.rawValue : WatchStatus.unwatched.rawValue, forKey: "statusRaw")
            episode.setValue(Int32(isWatched ? max(intValue(episode, forKey: "watchCount"), 1) : 0), forKey: "watchCount")
            episode.setValue(isWatched ? timestamp : nil, forKey: "watchedAt")
            episode.setValue(false, forKey: "isSkipped")
            episode.setValue(timestamp, forKey: "updatedAt")
        }

        try updateShowProgress(showLocalID: showLocalID, timestamp: timestamp)
        try saveIfNeeded()
    }

    func setShowCollected(showLocalID: String, isCollected: Bool) throws {
        let timestamp = now()
        for episode in try episodes(showLocalID: showLocalID, season: nil) {
            episode.setValue(isCollected, forKey: "isCollected")
            episode.setValue(timestamp, forKey: "updatedAt")
        }

        try saveIfNeeded()
    }

    func toggleEpisodeSkipped(localID: String) throws {
        let episode = try episodeState(localID: localID)
        let timestamp = now()
        let isCurrentlySkipped = (episode.value(forKey: "isSkipped") as? Bool ?? false)
            || stringValue(episode, forKey: "statusRaw") == WatchStatus.skipped.rawValue

        episode.setValue(isCurrentlySkipped == false, forKey: "isSkipped")
        episode.setValue(isCurrentlySkipped ? WatchStatus.unwatched.rawValue : WatchStatus.skipped.rawValue, forKey: "statusRaw")
        episode.setValue(Int32(0), forKey: "watchCount")
        episode.setValue(nil, forKey: "watchedAt")
        episode.setValue(timestamp, forKey: "updatedAt")

        try updateShowProgress(showLocalID: stringValue(episode, forKey: "showLocalID"), timestamp: timestamp)
        try saveIfNeeded()
    }

    func toggleEpisodeCollected(localID: String) throws {
        let episode = try episodeState(localID: localID)
        let timestamp = now()
        let current = episode.value(forKey: "isCollected") as? Bool ?? false

        episode.setValue(current == false, forKey: "isCollected")
        episode.setValue(timestamp, forKey: "updatedAt")

        try saveIfNeeded()
    }

    func markMovieWatched(localID: String) throws {
        let movie = try trackedItem(localID: localID, kind: .movie)
        let timestamp = now()
        let existingWatchCount = intValue(movie, forKey: "watchCount")

        movie.setValue(WatchStatus.watched.rawValue, forKey: "statusRaw")
        movie.setValue(Int32(max(existingWatchCount, 1)), forKey: "watchCount")
        movie.setValue(timestamp, forKey: "watchedAt")
        movie.setValue(timestamp, forKey: "updatedAt")

        try saveIfNeeded()
    }

    func watchMovieAgain(localID: String) throws {
        let movie = try trackedItem(localID: localID, kind: .movie)
        let timestamp = now()
        let existingWatchCount = intValue(movie, forKey: "watchCount")

        movie.setValue(WatchStatus.watched.rawValue, forKey: "statusRaw")
        movie.setValue(Int32(clamping: existingWatchCount + 1), forKey: "watchCount")
        movie.setValue(timestamp, forKey: "watchedAt")
        movie.setValue(timestamp, forKey: "updatedAt")

        try saveIfNeeded()
    }

    func markMovieUnwatched(localID: String) throws {
        let movie = try trackedItem(localID: localID, kind: .movie)
        let timestamp = now()

        movie.setValue(WatchStatus.unwatched.rawValue, forKey: "statusRaw")
        movie.setValue(Int32(0), forKey: "watchCount")
        movie.setValue(nil, forKey: "watchedAt")
        movie.setValue(timestamp, forKey: "updatedAt")

        try saveIfNeeded()
    }

    func toggleMovieCollected(localID: String) throws {
        let movie = try trackedItem(localID: localID, kind: .movie)
        let current = movie.value(forKey: "isCollected") as? Bool ?? false

        movie.setValue(current == false, forKey: "isCollected")
        movie.setValue(now(), forKey: "updatedAt")

        try saveIfNeeded()
    }

    func toggleFavorite(localID: String, kind: MediaKind) throws {
        let item = try trackedItem(localID: localID, kind: kind)
        let current = item.value(forKey: "isFavorite") as? Bool ?? false
        item.setValue(current == false, forKey: "isFavorite")
        item.setValue(now(), forKey: "updatedAt")

        try saveIfNeeded()
    }

    func toggleHidden(localID: String, kind: MediaKind) throws {
        let item = try trackedItem(localID: localID, kind: kind)
        let current = item.value(forKey: "isHidden") as? Bool ?? false
        item.setValue(current == false, forKey: "isHidden")
        item.setValue(now(), forKey: "updatedAt")

        try saveIfNeeded()
    }

    func updatePersonalDetails(
        localID: String,
        kind: MediaKind,
        userRating: Int?,
        notes: String?
    ) throws {
        let item = try trackedItem(localID: localID, kind: kind)
        setOptionalInt(normalizedRating(userRating), on: item, forKey: "userRating")
        item.setValue(normalizedNotes(notes), forKey: "notes")
        item.setValue(now(), forKey: "updatedAt")

        try saveIfNeeded()
    }

    func updateEpisodePersonalDetails(
        localID: String,
        userRating: Int?,
        notes: String?
    ) throws {
        let episode = try episodeState(localID: localID)
        setOptionalInt(normalizedRating(userRating), on: episode, forKey: "userRating")
        episode.setValue(normalizedNotes(notes), forKey: "notes")
        episode.setValue(now(), forKey: "updatedAt")

        try saveIfNeeded()
    }

    private func episodeState(localID: String) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", localID)

        guard let episode = try context.fetch(request).first else {
            throw WatchStateStoreError.episodeNotFound
        }

        return episode
    }

    private func trackedItem(localID: String, kind: MediaKind) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "localID == %@", localID),
            NSPredicate(format: "kindRaw == %@", kind.rawValue)
        ])

        guard let item = try context.fetch(request).first else {
            throw WatchStateStoreError.trackedItemNotFound
        }

        return item
    }

    private func episodes(showLocalID: String, season: Int?) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.returnsObjectsAsFaults = false
        if let season {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "showLocalID == %@", showLocalID),
                NSPredicate(format: "seasonNumber == %@", NSNumber(value: season))
            ])
        } else {
            request.predicate = NSPredicate(format: "showLocalID == %@", showLocalID)
        }
        return try context.fetch(request)
    }

    private func updateShowProgress(showLocalID: String, timestamp: Date) throws {
        guard showLocalID.isEmpty == false else {
            return
        }

        let episodeRequest = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        episodeRequest.returnsObjectsAsFaults = false
        episodeRequest.predicate = NSPredicate(format: "showLocalID == %@", showLocalID)
        let episodes = try context.fetch(episodeRequest)

        let watchedEpisodes = episodes.filter { episode in
            stringValue(episode, forKey: "statusRaw") == WatchStatus.watched.rawValue
                || intValue(episode, forKey: "watchCount") > 0
        }
        let totalPlays = episodes.reduce(Int32(0)) { total, episode in
            Int32(clamping: Int64(total) + Int64(intValue(episode, forKey: "watchCount")))
        }
        let latestWatchedAt = watchedEpisodes
            .compactMap { $0.value(forKey: "watchedAt") as? Date }
            .max()

        let showRequest = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        showRequest.fetchLimit = 1
        showRequest.predicate = NSPredicate(format: "localID == %@", showLocalID)

        guard let show = try context.fetch(showRequest).first else {
            return
        }

        show.setValue(totalPlays, forKey: "watchCount")
        show.setValue(latestWatchedAt, forKey: "watchedAt")
        show.setValue(showStatus(totalEpisodes: episodes.count, watchedEpisodes: watchedEpisodes.count).rawValue, forKey: "statusRaw")
        show.setValue(timestamp, forKey: "updatedAt")
    }

    private func showStatus(totalEpisodes: Int, watchedEpisodes: Int) -> WatchStatus {
        if watchedEpisodes == 0 {
            return .unwatched
        }

        if totalEpisodes > 0, watchedEpisodes >= totalEpisodes {
            return .watched
        }

        return .watching
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func normalizedRating(_ userRating: Int?) -> Int? {
        guard let userRating, (1...10).contains(userRating) else {
            return nil
        }

        return userRating
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setOptionalInt(_ value: Int?, on object: NSManagedObject, forKey key: String) {
        if let value {
            object.setValue(NSNumber(value: value), forKey: key)
        } else {
            object.setValue(nil, forKey: key)
        }
    }

    private func stringValue(_ object: NSManagedObject, forKey key: String) -> String {
        object.value(forKey: key) as? String ?? ""
    }

    private func intValue(_ object: NSManagedObject, forKey key: String) -> Int {
        if let number = object.value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return object.value(forKey: key) as? Int ?? 0
    }
}

enum WatchStateStoreError: Error {
    case episodeNotFound
    case trackedItemNotFound
}
