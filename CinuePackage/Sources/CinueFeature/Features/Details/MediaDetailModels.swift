import CoreData
import Foundation

struct MediaDetailSnapshot: Equatable, Identifiable {
    let id: String
    let item: LibraryItemSnapshot
    let backdropURL: URL?
    let overview: String?
    let sourceText: String?
    let notes: String?
    let userRating: Int?
    let isHidden: Bool
    let episodes: [EpisodeDetailSnapshot]
    let cast: [MediaDetailCreditSnapshot]
    let crew: [MediaDetailCreditSnapshot]
    let videos: [MediaDetailVideoSnapshot]
    let similarItems: [MediaDetailRelatedItemSnapshot]

    var title: String {
        item.title
    }

    var subtitle: String {
        [item.statusLabel, item.detailLine]
            .filter { $0.isEmpty == false }
            .joined(separator: " - ")
    }

    var nextEpisode: EpisodeDetailSnapshot? {
        nextEpisode(asOf: Date())
    }

    func nextEpisode(asOf: Date) -> EpisodeDetailSnapshot? {
        episodes.first {
            $0.isWatched == false
                && $0.isSkipped == false
                && EpisodeAvailability.isReleased(airDate: $0.airDate, asOf: asOf)
        }
    }

    func nextEpisode(after episode: EpisodeDetailSnapshot, asOf: Date = Date()) -> EpisodeDetailSnapshot? {
        episodes.first {
            $0.isWatched == false
                && $0.isSkipped == false
                && $0.isAfter(season: episode.seasonNumber, episode: episode.episodeNumber)
                && EpisodeAvailability.isReleased(airDate: $0.airDate, asOf: asOf)
        }
    }

    var artworkBackgroundURL: URL? {
        backdropURL ?? item.posterURL
    }

    var seasonGroups: [SeasonDetailSnapshot] {
        Dictionary(grouping: episodes, by: \.seasonNumber)
            .map { season, episodes in
                SeasonDetailSnapshot(seasonNumber: season, episodes: episodes.sorted { lhs, rhs in
                    (lhs.episodeNumber ?? Int.max, lhs.localID) < (rhs.episodeNumber ?? Int.max, rhs.localID)
                })
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }
}

struct SeasonDetailSnapshot: Equatable, Identifiable {
    var id: Int { seasonNumber }
    let seasonNumber: Int
    let episodes: [EpisodeDetailSnapshot]

    var title: String {
        seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"
    }

    var summary: String {
        let watched = episodes.filter(\.isWatched).count
        let collected = episodes.filter(\.isCollected).count
        var parts = ["\(watched) of \(episodes.count) watched"]
        if collected > 0 {
            parts.append("\(collected) collected")
        }
        return parts.joined(separator: " - ")
    }
}

struct MediaDetailCreditSnapshot: Equatable, Identifiable {
    let id: String
    let name: String
    let role: String?
    let imageURL: URL?
}

struct MediaDetailVideoSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let site: String
    let type: String
    let url: URL
}

struct MediaDetailRelatedItemSnapshot: Equatable, Identifiable {
    let id: String
    let kind: MediaKind
    let title: String
    let releaseDate: Date?
    let posterURL: URL?

    var releaseYear: String? {
        guard let releaseDate else {
            return nil
        }

        return Self.yearFormatter.string(from: releaseDate)
    }

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

struct EpisodeDetailSnapshot: Equatable, Identifiable {
    let id: String
    let localID: String
    let showLocalID: String
    let showTitle: String
    let title: String?
    let overview: String?
    let backdropURL: URL?
    let showBackdropURL: URL?
    let showPosterURL: URL?
    let seasonNumber: Int
    let episodeNumber: Int?
    let airDate: Date?
    let watchedAt: Date?
    let watchCount: Int
    let isWatched: Bool
    let isCollected: Bool
    let isSkipped: Bool
    let notes: String?
    let userRating: Int?

    var episodeCode: String {
        guard let episodeNumber else {
            return "S\(seasonNumber)"
        }

        return "\(seasonNumber)x\(String(format: "%02d", episodeNumber))"
    }

    var titleLine: String {
        guard let title, title.isEmpty == false else {
            return episodeCode
        }

        return "\(episodeCode) \(title)"
    }

    func displayTitleLine(hideSpoilers: Bool) -> String {
        hideSpoilers && isWatched == false ? episodeCode : titleLine
    }

    func displayOverview(hideSpoilers: Bool) -> String? {
        if hideSpoilers && isWatched == false {
            return "Episode summary hidden until watched."
        }

        return overview
    }

    var artworkBackgroundURL: URL? {
        backdropURL ?? showBackdropURL ?? showPosterURL
    }

    var stateLabel: String {
        if isWatched {
            return watchCount > 1 ? "Watched \(watchCount)x" : CinueCopy.State.watched
        }

        if isSkipped {
            return CinueCopy.State.skipped
        }

        if isCollected {
            return CinueCopy.State.inCollection
        }

        return CinueCopy.State.unwatched
    }

    var dateLine: String? {
        guard let airDate else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = CinuePreferences.useExactDates ? .full : .medium
        formatter.timeStyle = .none
        return formatter.string(from: airDate)
    }

    var releasedDateLine: String? {
        dateLine.map { "Released \($0)" }
    }

    var stateReleaseLine: String {
        [stateLabel, releasedDateLine]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var accessibilityLabel: String {
        [showTitle, titleLine, stateLabel, dateLine ?? ""]
            .filter { $0.isEmpty == false }
            .joined(separator: ", ")
    }
}

enum EpisodeAvailability {
    static func isReleased(airDate: Date?, asOf: Date) -> Bool {
        guard let airDate else {
            return false
        }

        return airDate <= asOf
    }
}

@MainActor
struct MediaDetailSnapshotBuilder {
    let context: NSManagedObjectContext

    func snapshot(localID: String, kind: MediaKind) -> MediaDetailSnapshot? {
        guard let trackedItem = fetchTrackedItem(localID: localID, kind: kind),
              let item = LibraryItemSnapshotBuilder(context: context).snapshots(from: [trackedItem]).first
        else {
            return nil
        }

        let metadata = metadataRecord(forKind: kind, localID: localID)
        let enrichment = tmdbEnrichment(from: metadata, fallbackKind: kind)
        let showBackdropURL = urlValue(metadata, forKey: "backdropURLString")
        let episodes = kind == .show
            ? episodeSnapshots(
                showLocalID: localID,
                showTitle: item.title,
                showBackdropURL: showBackdropURL,
                showPosterURL: item.posterURL
            )
            : []

        return MediaDetailSnapshot(
            id: item.localID,
            item: item,
            backdropURL: urlValue(metadata, forKey: "backdropURLString"),
            overview: stringValue(metadata, forKey: "overview").nilIfEmpty ?? item.overview,
            sourceText: stringValue(metadata, forKey: "attributionText").nilIfEmpty,
            notes: stringValue(trackedItem, forKey: "notes").nilIfEmpty,
            userRating: optionalIntValue(trackedItem, forKey: "userRating"),
            isHidden: boolValue(trackedItem, forKey: "isHidden"),
            episodes: episodes,
            cast: enrichment.cast,
            crew: enrichment.crew,
            videos: enrichment.videos,
            similarItems: enrichment.similarItems
        )
    }

    func episodeSnapshot(showLocalID: String, season: Int, episode: Int) -> EpisodeDetailSnapshot? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "showLocalID == %@", showLocalID),
            NSPredicate(format: "seasonNumber == %@", NSNumber(value: season)),
            NSPredicate(format: "episodeNumber == %@", NSNumber(value: episode))
        ])

        guard let episodeObject = try? context.fetch(request).first else {
            return nil
        }

        let showItem = fetchTrackedItem(localID: showLocalID, kind: .show)
        let showMetadata = metadataRecord(forKind: .show, localID: showLocalID)
        let showTitle = showItem.map { stringValue($0, forKey: "title", fallback: "Show") } ?? "Show"
        return episodeSnapshot(
            from: episodeObject,
            showTitle: showTitle,
            showBackdropURL: urlValue(showMetadata, forKey: "backdropURLString"),
            showPosterURL: urlValue(showMetadata, forKey: "posterURLString")
        )
    }

    func nextEpisode(
        afterShowLocalID showLocalID: String,
        season: Int,
        episode: Int,
        asOf: Date = Date()
    ) -> EpisodeDetailSnapshot? {
        let showItem = fetchTrackedItem(localID: showLocalID, kind: .show)
        let showMetadata = metadataRecord(forKind: .show, localID: showLocalID)
        let showTitle = showItem.map { stringValue($0, forKey: "title", fallback: "Show") } ?? "Show"
        let episodes = episodeSnapshots(
            showLocalID: showLocalID,
            showTitle: showTitle,
            showBackdropURL: urlValue(showMetadata, forKey: "backdropURLString"),
            showPosterURL: urlValue(showMetadata, forKey: "posterURLString")
        )

        return episodes.first {
            $0.isWatched == false
                && $0.isSkipped == false
                && $0.isAfter(season: season, episode: episode)
                && EpisodeAvailability.isReleased(airDate: $0.airDate, asOf: asOf)
        }
    }

    private func fetchTrackedItem(localID: String, kind: MediaKind) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "localID == %@", localID),
            NSPredicate(format: "kindRaw == %@", kind.rawValue)
        ])

        return try? context.fetch(request).first
    }

    private func episodeSnapshots(
        showLocalID: String,
        showTitle: String,
        showBackdropURL: URL?,
        showPosterURL: URL?
    ) -> [EpisodeDetailSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "showLocalID == %@", showLocalID)
        request.sortDescriptors = [
            NSSortDescriptor(key: "seasonNumber", ascending: true),
            NSSortDescriptor(key: "episodeNumber", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]

        do {
            return try context.fetch(request).compactMap { episode in
                episodeSnapshot(
                    from: episode,
                    showTitle: showTitle,
                    showBackdropURL: showBackdropURL,
                    showPosterURL: showPosterURL
                )
            }
        } catch {
            return []
        }
    }

    private func episodeSnapshot(
        from episode: NSManagedObject,
        showTitle: String,
        showBackdropURL: URL?,
        showPosterURL: URL?
    ) -> EpisodeDetailSnapshot {
        let localID = stringValue(episode, forKey: "localID")
        let metadata = episodeMetadataRecord(localID: localID)
        let statusRaw = stringValue(episode, forKey: "statusRaw")
        let watchCount = intValue(episode, forKey: "watchCount")
        let title = stringValue(episode, forKey: "title").nilIfEmpty
            ?? stringValue(metadata, forKey: "title").nilIfEmpty

        return EpisodeDetailSnapshot(
            id: localID,
            localID: localID,
            showLocalID: stringValue(episode, forKey: "showLocalID"),
            showTitle: showTitle,
            title: title,
            overview: stringValue(metadata, forKey: "overview").nilIfEmpty,
            backdropURL: urlValue(metadata, forKey: "backdropURLString"),
            showBackdropURL: showBackdropURL,
            showPosterURL: showPosterURL,
            seasonNumber: intValue(episode, forKey: "seasonNumber"),
            episodeNumber: optionalIntValue(episode, forKey: "episodeNumber"),
            airDate: metadata?.value(forKey: "releaseDate") as? Date,
            watchedAt: episode.value(forKey: "watchedAt") as? Date,
            watchCount: watchCount,
            isWatched: statusRaw == WatchStatus.watched.rawValue || watchCount > 0,
            isCollected: boolValue(episode, forKey: "isCollected") || statusRaw == WatchStatus.collected.rawValue,
            isSkipped: boolValue(episode, forKey: "isSkipped") || statusRaw == WatchStatus.skipped.rawValue,
            notes: stringValue(episode, forKey: "notes").nilIfEmpty,
            userRating: optionalIntValue(episode, forKey: "userRating")
        )
    }

    private func metadataRecord(forKind kind: MediaKind, localID: String) -> NSManagedObject? {
        fetchMetadataRecord(
            cacheIDs: [
                "seriesguide:\(kind.rawValue):\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: kind.rawValue, localID: localID)
            ]
        )
    }

    private func episodeMetadataRecord(localID: String) -> NSManagedObject? {
        fetchMetadataRecord(
            cacheIDs: [
                "seriesguide:episode:\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: localID)
            ]
        )
    }

    private func fetchMetadataRecord(cacheIDs: [String]) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)

        return try? context.fetch(request).first
    }

    private func tmdbEnrichment(
        from metadata: NSManagedObject?,
        fallbackKind: MediaKind
    ) -> TMDBDetailEnrichment {
        guard let rawJSON = metadata?.value(forKey: "rawJSON") as? Data,
              let payload = try? JSONDecoder().decode(TMDBAppendedDetailPayload.self, from: rawJSON)
        else {
            return TMDBDetailEnrichment()
        }

        let cast = (payload.credits?.cast ?? [])
            .sorted { ($0.order ?? Int.max, $0.name ?? "") < ($1.order ?? Int.max, $1.name ?? "") }
            .prefix(12)
            .compactMap { credit -> MediaDetailCreditSnapshot? in
                guard let name = credit.name?.nilIfEmpty else {
                    return nil
                }

                return MediaDetailCreditSnapshot(
                    id: "cast:\(credit.id ?? 0):\(name)",
                    name: name,
                    role: credit.character?.nilIfEmpty,
                    imageURL: Self.tmdbImageURL(path: credit.profilePath, size: .poster)
                )
            }

        let crew = (payload.credits?.crew ?? [])
            .filter { ["Creator", "Director", "Writer", "Screenplay"].contains($0.job ?? "") }
            .prefix(8)
            .compactMap { credit -> MediaDetailCreditSnapshot? in
                guard let name = credit.name?.nilIfEmpty else {
                    return nil
                }

                return MediaDetailCreditSnapshot(
                    id: "crew:\(credit.id ?? 0):\(name):\(credit.job ?? "")",
                    name: name,
                    role: credit.job?.nilIfEmpty ?? credit.department?.nilIfEmpty,
                    imageURL: Self.tmdbImageURL(path: credit.profilePath, size: .poster)
                )
            }

        let videos = (payload.videos?.results ?? [])
            .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .sorted { lhs, rhs in
                if lhs.official != rhs.official {
                    return lhs.official == true
                }

                return (lhs.name ?? "") < (rhs.name ?? "")
            }
            .prefix(4)
            .compactMap { video -> MediaDetailVideoSnapshot? in
                guard let key = video.key?.nilIfEmpty,
                      let title = video.name?.nilIfEmpty,
                      let url = URL(string: "https://www.youtube.com/watch?v=\(key)")
                else {
                    return nil
                }

                return MediaDetailVideoSnapshot(
                    id: video.id ?? key,
                    title: title,
                    site: video.site ?? "YouTube",
                    type: video.type ?? "Video",
                    url: url
                )
            }

        let similarItems = (payload.similar?.results ?? [])
            .prefix(10)
            .compactMap { item -> MediaDetailRelatedItemSnapshot? in
                let kind = item.mediaKind ?? fallbackKind
                let title = item.title(for: kind)?.nilIfEmpty
                guard let title else {
                    return nil
                }

                return MediaDetailRelatedItemSnapshot(
                    id: "similar:\(kind.rawValue):\(item.id)",
                    kind: kind,
                    title: title,
                    releaseDate: Self.parseDate(item.releaseDate ?? item.firstAirDate),
                    posterURL: Self.tmdbImageURL(path: item.posterPath, size: .poster)
                )
            }

        return TMDBDetailEnrichment(
            cast: Array(cast),
            crew: Array(crew),
            videos: Array(videos),
            similarItems: Array(similarItems)
        )
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

    private static func tmdbImageURL(path: String?, size: TMDBArtworkSize) -> URL? {
        TMDBArtworkURL.make(path: path, size: size)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct TMDBDetailEnrichment {
    var cast: [MediaDetailCreditSnapshot] = []
    var crew: [MediaDetailCreditSnapshot] = []
    var videos: [MediaDetailVideoSnapshot] = []
    var similarItems: [MediaDetailRelatedItemSnapshot] = []
}

private struct TMDBAppendedDetailPayload: Decodable {
    var credits: TMDBCreditsPayload?
    var videos: TMDBVideosPayload?
    var similar: TMDBSimilarPayload?
}

private struct TMDBCreditsPayload: Decodable {
    var cast: [TMDBCreditPayload]?
    var crew: [TMDBCreditPayload]?
}

private struct TMDBCreditPayload: Decodable {
    var id: Int?
    var name: String?
    var character: String?
    var job: String?
    var department: String?
    var profilePath: String?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case character
        case job
        case department
        case profilePath = "profile_path"
        case order
    }
}

private struct TMDBVideosPayload: Decodable {
    var results: [TMDBVideoPayload]?
}

private struct TMDBVideoPayload: Decodable {
    var id: String?
    var name: String?
    var key: String?
    var site: String?
    var type: String?
    var official: Bool?
}

private struct TMDBSimilarPayload: Decodable {
    var results: [TMDBSimilarItemPayload]?
}

private struct TMDBSimilarItemPayload: Decodable {
    var id: Int
    var mediaType: String?
    var title: String?
    var name: String?
    var releaseDate: String?
    var firstAirDate: String?
    var posterPath: String?

    var mediaKind: MediaKind? {
        switch mediaType {
        case "movie":
            return .movie
        case "tv":
            return .show
        default:
            if title?.isEmpty == false {
                return .movie
            }
            if name?.isEmpty == false {
                return .show
            }
            return nil
        }
    }

    func title(for kind: MediaKind) -> String? {
        switch kind {
        case .movie:
            return title ?? name
        case .show:
            return name ?? title
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
    }
}

private extension EpisodeDetailSnapshot {
    func isAfter(season otherSeason: Int, episode otherEpisode: Int?) -> Bool {
        if seasonNumber != otherSeason {
            return seasonNumber > otherSeason
        }

        return (episodeNumber ?? Int.max) > (otherEpisode ?? Int.max)
    }
}
