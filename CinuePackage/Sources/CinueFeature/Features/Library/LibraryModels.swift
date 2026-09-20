import CoreData
import Foundation

struct LibraryItemSnapshot: Equatable, Identifiable {
    let id: String
    let localID: String
    let tvdbID: Int?
    let tmdbID: Int?
    let kind: MediaKind
    let title: String
    let posterURL: URL?
    let overview: String?
    let releaseDate: Date?
    let statusLabel: String
    let detailLine: String
    let secondaryLine: String?
    let providerStatusLabel: String?
    let isFavorite: Bool
    let isCollected: Bool
    let isHidden: Bool
    let watchCount: Int

    var accessibilityLabel: String {
        [title, kindTitle, providerStatusLabel, statusLabel, isHidden ? "Hidden" : nil, detailLine]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }
            .joined(separator: ", ")
    }

    var kindTitle: String {
        kind == .movie ? "Movie" : "Show"
    }
}

@MainActor
struct LibraryItemSnapshotBuilder {
    let context: NSManagedObjectContext

    func snapshots(from trackedItems: [NSManagedObject]) -> [LibraryItemSnapshot] {
        let metadataByCacheID = fetchMetadataRecords(for: trackedItems)
        let episodeStatsByShowID = fetchEpisodeStats(for: trackedItems)

        return trackedItems.map { item in
            let localID = stringValue(item, forKey: "localID")
            let kind = MediaKind(rawValue: stringValue(item, forKey: "kindRaw")) ?? .show
            let title = stringValue(item, forKey: "title", fallback: "Untitled")
            let watchCount = intValue(item, forKey: "watchCount")
            let statusRaw = stringValue(item, forKey: "statusRaw", fallback: WatchStatus.unwatched.rawValue)
            let isFavorite = boolValue(item, forKey: "isFavorite")
            let isCollected = boolValue(item, forKey: "isCollected")
            let isHidden = boolValue(item, forKey: "isHidden")
            let metadata = metadataRecord(
                forKind: kind,
                localID: localID,
                metadataByCacheID: metadataByCacheID
            )
            let stats = episodeStatsByShowID[localID]

            return LibraryItemSnapshot(
                id: localID,
                localID: localID,
                tvdbID: optionalIntValue(item, forKey: "tvdbID"),
                tmdbID: optionalIntValue(item, forKey: "tmdbID"),
                kind: kind,
                title: title,
                posterURL: urlValue(metadata, forKey: "posterURLString"),
                overview: stringValue(metadata, forKey: "overview").nilIfEmpty,
                releaseDate: metadata?.value(forKey: "releaseDate") as? Date,
                statusLabel: statusLabel(kind: kind, statusRaw: statusRaw, watchCount: watchCount, episodeStats: stats),
                detailLine: detailLine(kind: kind, watchCount: watchCount, isFavorite: isFavorite, isCollected: isCollected, episodeStats: stats),
                secondaryLine: secondaryLine(for: metadata),
                providerStatusLabel: providerStatusLabel(kind: kind, metadata: metadata),
                isFavorite: isFavorite,
                isCollected: isCollected,
                isHidden: isHidden,
                watchCount: watchCount
            )
        }
    }

    private func metadataRecord(
        forKind kind: MediaKind,
        localID: String,
        metadataByCacheID: [String: NSManagedObject]
    ) -> NSManagedObject? {
        metadataByCacheID["seriesguide:\(kind.rawValue):\(localID)"]
            ?? metadataByCacheID[ContentLibraryStore.metadataCacheID(kindRaw: kind.rawValue, localID: localID)]
    }

    private func fetchMetadataRecords(for trackedItems: [NSManagedObject]) -> [String: NSManagedObject] {
        let cacheIDs = trackedItems.flatMap { item in
            let localID = stringValue(item, forKey: "localID")
            let kindRaw = stringValue(item, forKey: "kindRaw")
            return [
                "seriesguide:\(kindRaw):\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: kindRaw, localID: localID)
            ]
        }

        guard cacheIDs.isEmpty == false else {
            return [:]
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)

        do {
            return try context.fetch(request).reduce(into: [:]) { result, object in
                let cacheID = stringValue(object, forKey: "cacheID")
                if cacheID.isEmpty == false {
                    result[cacheID] = object
                }
            }
        } catch {
            return [:]
        }
    }

    private func fetchEpisodeStats(for trackedItems: [NSManagedObject]) -> [String: EpisodeProgress] {
        let showLocalIDs = trackedItems
            .filter { stringValue($0, forKey: "kindRaw") == MediaKind.show.rawValue }
            .map { stringValue($0, forKey: "localID") }
            .filter { $0.isEmpty == false }

        guard showLocalIDs.isEmpty == false else {
            return [:]
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "showLocalID IN %@", showLocalIDs)

        do {
            return try context.fetch(request).reduce(into: [:]) { result, episode in
                let showLocalID = stringValue(episode, forKey: "showLocalID")
                var progress = result[showLocalID] ?? EpisodeProgress()
                progress.total += 1

                let statusRaw = stringValue(episode, forKey: "statusRaw")
                let watchCount = intValue(episode, forKey: "watchCount")
                if statusRaw == WatchStatus.watched.rawValue || watchCount > 0 {
                    progress.watched += 1
                }
                if boolValue(episode, forKey: "isSkipped") || statusRaw == WatchStatus.skipped.rawValue {
                    progress.skipped += 1
                }
                if boolValue(episode, forKey: "isCollected") || statusRaw == WatchStatus.collected.rawValue {
                    progress.collected += 1
                }

                result[showLocalID] = progress
            }
        } catch {
            return [:]
        }
    }

    private func statusLabel(
        kind: MediaKind,
        statusRaw: String,
        watchCount: Int,
        episodeStats: EpisodeProgress?
    ) -> String {
        if kind == .movie {
            return watchCount > 0 || statusRaw == WatchStatus.watched.rawValue ? CinueCopy.State.watched : CinueCopy.State.unwatched
        }

        if let episodeStats, episodeStats.total > 0, episodeStats.watched == episodeStats.total {
            return "Finished"
        }

        if watchCount > 0 || statusRaw == WatchStatus.watching.rawValue {
            return "Watching"
        }

        return CinueCopy.State.unwatched
    }

    private func detailLine(
        kind: MediaKind,
        watchCount: Int,
        isFavorite: Bool,
        isCollected: Bool,
        episodeStats: EpisodeProgress?
    ) -> String {
        if kind == .movie {
            if watchCount == 1 {
                return "Watched once"
            }

            if watchCount > 1 {
                return "\(watchCount) plays"
            }

            if isCollected {
                return CinueCopy.State.inCollection
            }

            return isFavorite ? CinueCopy.State.onWatchlist : "Not watched yet"
        }

        guard let episodeStats, episodeStats.total > 0 else {
            if watchCount == 0 {
                return "No watched episodes yet"
            }
            return watchCount == 1 ? "1 watched episode" : "\(watchCount) watched episodes"
        }

        var parts = ["\(episodeStats.watched) of \(episodeStats.total) episodes watched"]
        if episodeStats.skipped > 0 {
            parts.append("\(episodeStats.skipped) skipped")
        }
        if episodeStats.collected > 0 {
            parts.append("\(episodeStats.collected) collected")
        }
        return parts.joined(separator: " - ")
    }

    private func secondaryLine(for metadata: NSManagedObject?) -> String? {
        guard let metadata else {
            return nil
        }

        if let releaseDate = metadata.value(forKey: "releaseDate") as? Date {
            return Self.releaseYearFormatter.string(from: releaseDate)
        }

        return stringValue(metadata, forKey: "overview").nilIfEmpty
    }

    private func providerStatusLabel(kind: MediaKind, metadata: NSManagedObject?) -> String? {
        guard kind == .show,
              let rawJSON = metadata?.value(forKey: "rawJSON") as? Data
        else {
            return nil
        }

        let payload = try? JSONDecoder().decode(ProviderStatusPayload.self, from: rawJSON)
        return ProviderStatusNormalizer.normalized(payload?.status)
    }

    private func urlValue(_ object: NSManagedObject?, forKey key: String) -> URL? {
        guard let string = stringValue(object, forKey: key).nilIfEmpty else {
            return nil
        }

        guard let candidate = URL(string: string) else {
            return nil
        }

        return try? ArtworkURLPolicy.tmdb.canonicalURL(for: candidate)
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

    private static let releaseYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

private struct ProviderStatusPayload: Decodable {
    var status: String?
}

private struct EpisodeProgress: Equatable {
    var total = 0
    var watched = 0
    var skipped = 0
    var collected = 0
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
