import CoreData
import Foundation

struct MetadataRefreshSummary: Equatable {
    var refreshedItems = 0
    var refreshedEpisodes = 0
    var skippedFreshItems = 0
    var failedItems = 0
    var failureReason: MetadataProviderError?
}

@MainActor
final class MetadataRefreshService {
    private let persistence: PersistenceController
    private let tmdbClient: TMDBClient
    private let now: @Sendable () -> Date
    private let staleInterval: TimeInterval
    private let maxItemsPerRun: Int
    private let metadataCleanupContext: NSManagedObjectContext

    init(
        persistence: PersistenceController,
        tmdbClient: TMDBClient,
        now: @escaping @Sendable () -> Date = Date.init,
        staleInterval: TimeInterval = 60 * 60 * 24,
        maxItemsPerRun: Int = 20,
        metadataCleanupContext: NSManagedObjectContext? = nil
    ) {
        self.persistence = persistence
        self.tmdbClient = tmdbClient
        self.now = now
        self.staleInterval = staleInterval
        self.maxItemsPerRun = maxItemsPerRun
        self.metadataCleanupContext = metadataCleanupContext ?? persistence.container.newBackgroundContext()
    }

    func refreshStaleMetadata(force: Bool = false) async -> MetadataRefreshSummary {
        let context = persistence.container.viewContext
        var summary = MetadataRefreshSummary()
        do {
            try await purgeExpiredTMDBMetadata()
        } catch {
            summary.failedItems = 1
            return summary
        }

        if force == false {
            summary.skippedFreshItems = freshTrackedItemCount(in: context)
        }
        let candidates = trackedItemsNeedingRefresh(in: context, force: force)
            .prefix(maxItemsPerRun)

        for item in candidates {
            let kind = MediaKind(rawValue: item.stringValue(forKey: "kindRaw")) ?? .show
            guard let tmdbID = item.optionalIntValue(forKey: "tmdbID") else {
                summary.failedItems += 1
                continue
            }

            do {
                let details = try await tmdbClient.details(kind: kind, tmdbID: tmdbID)
                let refreshedEpisodeCount = try upsert(details: details, for: item, in: context)
                summary.refreshedItems += 1
                summary.refreshedEpisodes += refreshedEpisodeCount
            } catch let error as MetadataProviderError {
                summary.failedItems += 1
                summary.failureReason = summary.failureReason ?? error
                if error == .missingAPIKey {
                    break
                }
            } catch {
                summary.failedItems += 1
            }
        }

        return summary
    }

    func refreshMetadata(localID: String, kind: MediaKind) async -> MetadataRefreshSummary {
        let context = persistence.container.viewContext
        var summary = MetadataRefreshSummary()

        guard let item = trackedItem(localID: localID, kind: kind, in: context),
              let tmdbID = item.optionalIntValue(forKey: "tmdbID")
        else {
            summary.failedItems = 1
            return summary
        }

        do {
            let details = try await tmdbClient.details(kind: kind, tmdbID: tmdbID)
            let refreshedEpisodeCount = try upsert(details: details, for: item, in: context)
            summary.refreshedItems = 1
            summary.refreshedEpisodes = refreshedEpisodeCount
        } catch let error as MetadataProviderError {
            summary.failedItems = 1
            summary.failureReason = error
        } catch {
            summary.failedItems = 1
        }

        return summary
    }

    private func trackedItemsNeedingRefresh(in context: NSManagedObjectContext, force: Bool) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "isHidden == NO AND tmdbID != nil")
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: true),
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        let items = (try? context.fetch(request)) ?? []
        guard force == false else {
            return items
        }

        return items.filter { item in
            guard let metadata = metadataRecord(for: item, in: context) else {
                return true
            }

            return isFreshProviderMetadata(metadata) == false
        }
    }

    private func freshTrackedItemCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "isHidden == NO AND tmdbID != nil")

        return ((try? context.fetch(request)) ?? []).filter { item in
            guard let metadata = metadataRecord(for: item, in: context) else {
                return false
            }

            return isFreshProviderMetadata(metadata)
        }.count
    }

    private func purgeExpiredTMDBMetadata() async throws {
        let expirationDate = now()
        try await metadataCleanupContext.perform {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "providerRaw == %@", MetadataProviderID.tmdb.rawValue),
                    NSPredicate(format: "expiresAt != nil AND expiresAt <= %@", expirationDate as NSDate)
                ])

                let expiredRecords = try self.metadataCleanupContext.fetch(request)
                expiredRecords.forEach(self.metadataCleanupContext.delete)

                if expiredRecords.isEmpty == false {
                    try self.metadataCleanupContext.save()
                }
            } catch {
                self.metadataCleanupContext.rollback()
                throw error
            }
        }
    }

    private func trackedItem(localID: String, kind: MediaKind, in context: NSManagedObjectContext) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "localID == %@", localID),
            NSPredicate(format: "kindRaw == %@", kind.rawValue)
        ])
        return try? context.fetch(request).first
    }

    private func isFreshProviderMetadata(_ metadata: NSManagedObject) -> Bool {
        guard metadata.stringValue(forKey: "providerRaw") == MetadataProviderID.tmdb.rawValue,
              let fetchedAt = metadata.value(forKey: "fetchedAt") as? Date
        else {
            return false
        }

        return now().timeIntervalSince(fetchedAt) < staleInterval
    }

    private func upsert(
        details: RefreshedMediaDetails,
        for item: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let timestamp = now()
        item.setValue(details.title, forKey: "title")
        item.setValue(details.title.localizedLowercase, forKey: "sortTitle")
        item.setOptionalInt(details.contentIDs.tmdbID, forKey: "tmdbID")
        item.setValue(timestamp, forKey: "updatedAt")

        try upsertMetadataRecord(
            cacheID: metadataCacheID(for: item, kind: details.kind, in: context),
            details: details,
            kindRaw: details.kind.rawValue,
            rawJSON: details.rawJSON,
            in: context
        )

        let refreshedEpisodes = try details.episodes.reduce(0) { count, episode in
            try upsertEpisode(episode, showItem: item, showTMDBID: details.contentIDs.tmdbID, in: context)
                ? count + 1
                : count
        }

        if details.kind == .show {
            try updateShowProgress(showLocalID: item.stringValue(forKey: "localID"), timestamp: timestamp, in: context)
        }

        if context.hasChanges {
            try context.save()
        }

        return refreshedEpisodes
    }

    @discardableResult
    private func upsertEpisode(
        _ episode: RefreshedEpisodeDetails,
        showItem: NSManagedObject,
        showTMDBID: Int?,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let timestamp = now()
        let showLocalID = showItem.stringValue(forKey: "localID")
        let existing = existingEpisode(for: episode, showLocalID: showLocalID, in: context)
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "EpisodeState", into: context)
        let isInsert = existing == nil
        let localID = existing?.stringValue(forKey: "localID") ?? episodeLocalID(for: episode, showLocalID: showLocalID)

        if isInsert {
            object.setValue(localID, forKey: "localID")
            object.setValue(WatchStatus.unwatched.rawValue, forKey: "statusRaw")
            object.setValue(Int32(0), forKey: "watchCount")
            object.setValue(false, forKey: "isCollected")
            object.setValue(false, forKey: "isSkipped")
            object.setValue(timestamp, forKey: "createdAt")
        }

        object.setValue(showLocalID, forKey: "showLocalID")
        object.setValue(Int32(episode.seasonNumber), forKey: "seasonNumber")
        object.setValue(Int32(episode.episodeNumber), forKey: "episodeNumber")
        object.setValue(episode.title, forKey: "title")
        object.setOptionalInt(episode.tmdbID, forKey: "tmdbID")
        object.setValue(timestamp, forKey: "updatedAt")

        try upsertEpisodeMetadataRecord(
            cacheID: episodeMetadataCacheID(for: object, in: context),
            episode: episode,
            showTMDBID: showTMDBID,
            in: context
        )

        return isInsert
    }

    private func upsertMetadataRecord(
        cacheID: String,
        details: RefreshedMediaDetails,
        kindRaw: String,
        rawJSON: Data?,
        in context: NSManagedObjectContext
    ) throws {
        let object = metadataRecord(cacheID: cacheID, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: "MetadataRecord", into: context)
        let timestamp = now()

        object.setValue(cacheID, forKey: "cacheID")
        object.setValue(details.attribution.providerID.rawValue, forKey: "providerRaw")
        object.setValue(providerContentID(for: details), forKey: "providerContentID")
        object.setValue(kindRaw, forKey: "kindRaw")
        object.setValue(details.title, forKey: "title")
        object.setValue(details.overview, forKey: "overview")
        object.setValue(details.posterURL?.absoluteString, forKey: "posterURLString")
        object.setValue(details.backdropURL?.absoluteString, forKey: "backdropURLString")
        object.setValue(details.releaseDate, forKey: "releaseDate")
        object.setValue(details.sourceURLString, forKey: "sourceURLString")
        object.setValue(details.attribution.requiredText, forKey: "attributionText")
        object.setValue(rawJSON, forKey: "rawJSON")
        object.setValue(timestamp, forKey: "fetchedAt")
        object.setValue(Calendar.current.date(byAdding: .month, value: 6, to: timestamp), forKey: "expiresAt")
    }

    private func upsertEpisodeMetadataRecord(
        cacheID: String,
        episode: RefreshedEpisodeDetails,
        showTMDBID: Int?,
        in context: NSManagedObjectContext
    ) throws {
        let object = metadataRecord(cacheID: cacheID, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: "MetadataRecord", into: context)
        let timestamp = now()

        object.setValue(cacheID, forKey: "cacheID")
        object.setValue(MetadataProviderID.tmdb.rawValue, forKey: "providerRaw")
        object.setValue(episode.tmdbID.map { "tmdb:\($0)" } ?? "\(episode.seasonNumber)x\(episode.episodeNumber)", forKey: "providerContentID")
        object.setValue("episode", forKey: "kindRaw")
        object.setValue(episode.title, forKey: "title")
        object.setValue(episode.overview, forKey: "overview")
        object.setValue(nil, forKey: "posterURLString")
        object.setValue(episode.imageURL?.absoluteString, forKey: "backdropURLString")
        object.setValue(episode.airDate, forKey: "releaseDate")
        object.setValue(episode.sourceURLString ?? fallbackEpisodeSourceURL(showTMDBID: showTMDBID, episode: episode), forKey: "sourceURLString")
        object.setValue(ProviderAttribution.tmdb.requiredText, forKey: "attributionText")
        object.setValue(episode.rawJSON, forKey: "rawJSON")
        object.setValue(timestamp, forKey: "fetchedAt")
        object.setValue(Calendar.current.date(byAdding: .month, value: 6, to: timestamp), forKey: "expiresAt")
    }

    private func existingEpisode(
        for episode: RefreshedEpisodeDetails,
        showLocalID: String,
        in context: NSManagedObjectContext
    ) -> NSManagedObject? {
        var predicates: [NSPredicate] = [
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "showLocalID == %@", showLocalID),
                NSPredicate(format: "seasonNumber == %@", NSNumber(value: episode.seasonNumber)),
                NSPredicate(format: "episodeNumber == %@", NSNumber(value: episode.episodeNumber))
            ])
        ]

        if let tmdbID = episode.tmdbID {
            predicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "showLocalID == %@", showLocalID),
                NSPredicate(format: "tmdbID == %@", NSNumber(value: tmdbID))
            ]))
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        return try? context.fetch(request).first
    }

    private func updateShowProgress(showLocalID: String, timestamp: Date, in context: NSManagedObjectContext) throws {
        let episodeRequest = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        episodeRequest.predicate = NSPredicate(format: "showLocalID == %@", showLocalID)
        let episodes = try context.fetch(episodeRequest)
        let watched = episodes.filter { episode in
            episode.stringValue(forKey: "statusRaw") == WatchStatus.watched.rawValue
                || episode.intValue(forKey: "watchCount") > 0
        }
        let maximumPlayCount = Int64(Int32.max)
        let totalPlays = episodes.reduce(Int64(0)) { total, episode in
            min(maximumPlayCount, total + Int64(max(0, episode.intValue(forKey: "watchCount"))))
        }

        let showRequest = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        showRequest.fetchLimit = 1
        showRequest.predicate = NSPredicate(format: "localID == %@", showLocalID)

        guard let show = try context.fetch(showRequest).first else {
            return
        }

        show.setValue(Int32(totalPlays), forKey: "watchCount")
        show.setValue(showStatus(totalEpisodes: episodes.count, watchedEpisodes: watched.count).rawValue, forKey: "statusRaw")
        show.setValue(watched.compactMap { $0.value(forKey: "watchedAt") as? Date }.max(), forKey: "watchedAt")
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

    private func metadataRecord(for item: NSManagedObject, in context: NSManagedObjectContext) -> NSManagedObject? {
        let kindRaw = item.stringValue(forKey: "kindRaw")
        let localID = item.stringValue(forKey: "localID")
        return metadataRecord(
            cacheIDs: [
                "seriesguide:\(kindRaw):\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: kindRaw, localID: localID)
            ],
            in: context
        )
    }

    private func metadataCacheID(for item: NSManagedObject, kind: MediaKind, in context: NSManagedObjectContext) -> String {
        let localID = item.stringValue(forKey: "localID")
        let seriesGuideCacheID = "seriesguide:\(kind.rawValue):\(localID)"
        if metadataRecord(cacheID: seriesGuideCacheID, in: context) != nil {
            return seriesGuideCacheID
        }

        return ContentLibraryStore.metadataCacheID(kindRaw: kind.rawValue, localID: localID)
    }

    private func episodeMetadataCacheID(for episode: NSManagedObject, in context: NSManagedObjectContext) -> String {
        let localID = episode.stringValue(forKey: "localID")
        let seriesGuideCacheID = "seriesguide:episode:\(localID)"
        if metadataRecord(cacheID: seriesGuideCacheID, in: context) != nil {
            return seriesGuideCacheID
        }

        return ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: localID)
    }

    private func metadataRecord(cacheID: String, in context: NSManagedObjectContext) -> NSManagedObject? {
        metadataRecord(cacheIDs: [cacheID], in: context)
    }

    private func metadataRecord(cacheIDs: [String], in context: NSManagedObjectContext) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)
        return try? context.fetch(request).first
    }

    private func providerContentID(for details: RefreshedMediaDetails) -> String {
        if let tmdbID = details.contentIDs.tmdbID {
            return "tmdb:\(tmdbID)"
        }

        return details.sourceURLString ?? details.title
    }

    private func episodeLocalID(for episode: RefreshedEpisodeDetails, showLocalID: String) -> String {
        if let tmdbID = episode.tmdbID {
            return "provider:episode:\(showLocalID):tmdb:\(tmdbID)"
        }

        return "provider:episode:\(showLocalID):s\(episode.seasonNumber)e\(episode.episodeNumber)"
    }

    private func fallbackEpisodeSourceURL(showTMDBID: Int?, episode: RefreshedEpisodeDetails) -> String? {
        guard let showTMDBID else {
            return nil
        }

        return "https://www.themoviedb.org/tv/\(showTMDBID)/season/\(episode.seasonNumber)/episode/\(episode.episodeNumber)"
    }
}

private extension NSManagedObject {
    func stringValue(forKey key: String) -> String {
        value(forKey: key) as? String ?? ""
    }

    func intValue(forKey key: String) -> Int {
        if let number = value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return value(forKey: key) as? Int ?? 0
    }

    func optionalIntValue(forKey key: String) -> Int? {
        if let number = value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return value(forKey: key) as? Int
    }

    func setOptionalInt(_ value: Int?, forKey key: String) {
        if let value {
            setValue(value, forKey: key)
        } else {
            setValue(nil, forKey: key)
        }
    }
}
