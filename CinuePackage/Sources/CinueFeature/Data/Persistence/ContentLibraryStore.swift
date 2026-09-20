import CoreData
import Foundation

enum ListMoveDirection: Sendable {
    case earlier
    case later
}

enum ListItemSortMode: Sendable {
    case titleAscending
    case titleDescending
    case titleAscendingIgnoringArticles
    case mediaKindThenTitle
    case latestEpisode
    case oldestEpisode
    case lastWatched
    case leastRemainingEpisodes
}

@MainActor
struct ContentLibraryStore {
    private let context: NSManagedObjectContext
    private let now: () -> Date

    init(context: NSManagedObjectContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    func isTracked(_ item: MediaSummary) throws -> Bool {
        try existingTrackedItem(for: item) != nil
    }

    func isInWatchlist(_ item: MediaSummary) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "listLocalID == %@", Self.watchlistLocalID),
            identityPredicate(for: item, stableLocalID: Self.stableLocalID(for: item))
        ])

        return try context.fetch(request).isEmpty == false
    }

    @discardableResult
    func addToLibrary(_ item: MediaSummary) throws -> String {
        let stableLocalID = Self.stableLocalID(for: item)
        let existing = try existingTrackedItem(for: item)
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "TrackedItem", into: context)
        let timestamp = now()

        if existing == nil {
            object.setValue(stableLocalID, forKey: "localID")
            object.setValue(timestamp, forKey: "createdAt")
            object.setValue(WatchStatus.unwatched.rawValue, forKey: "statusRaw")
            object.setValue(Int32(0), forKey: "watchCount")
            object.setValue(false, forKey: "isCollected")
            object.setValue(false, forKey: "isFavorite")
            object.setValue(false, forKey: "isHidden")
        }

        object.setValue(item.kind.rawValue, forKey: "kindRaw")
        object.setValue(item.title, forKey: "title")
        object.setValue(item.title.localizedLowercase, forKey: "sortTitle")
        if existing == nil || item.contentIDs.tvdbID != nil {
            object.setOptionalInt(item.contentIDs.tvdbID, forKey: "tvdbID")
        }
        if existing == nil || item.contentIDs.tmdbID != nil {
            object.setOptionalInt(item.contentIDs.tmdbID, forKey: "tmdbID")
        }
        if existing == nil || item.contentIDs.imdbID != nil {
            object.setValue(item.contentIDs.imdbID, forKey: "imdbID")
        }
        object.setValue(timestamp, forKey: "updatedAt")

        upsertMetadataRecord(for: item, localID: object.stringValue(forKey: "localID"), timestamp: timestamp)
        try saveIfNeeded()
        return object.stringValue(forKey: "localID")
    }

    func addToWatchlist(_ item: MediaSummary) throws {
        let itemLocalID = try addToLibrary(item)
        let timestamp = now()
        let list = try upsertWatchlist(timestamp: timestamp)
        let listLocalID = list.stringValue(forKey: "localID")
        let localID = "cinue:listitem:watchlist:\(itemLocalID)"

        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", localID)
        let existing = try context.fetch(request).first
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "UserListItem", into: context)

        if existing == nil {
            object.setValue(localID, forKey: "localID")
            object.setValue(timestamp, forKey: "createdAt")
            object.setValue(Int32(0), forKey: "sortOrder")
        }

        object.setValue(listLocalID, forKey: "listLocalID")
        object.setValue(itemLocalID, forKey: "itemLocalID")
        object.setValue(providerExternalID(for: item), forKey: "externalID")
        object.setValue(item.kind.rawValue, forKey: "kindRaw")
        object.setOptionalInt(item.contentIDs.tvdbID, forKey: "tvdbID")
        object.setOptionalInt(item.contentIDs.tmdbID, forKey: "tmdbID")
        object.setValue(timestamp, forKey: "updatedAt")

        try saveIfNeeded()
    }

    @discardableResult
    func createUserList(name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw ContentLibraryStoreError.emptyListName
        }

        let timestamp = now()
        let object = NSEntityDescription.insertNewObject(forEntityName: "UserList", into: context)
        let localID = "cinue:list:\(UUID().uuidString)"
        object.setValue(localID, forKey: "localID")
        object.setValue(trimmedName, forKey: "name")
        object.setValue(Int32(nextListSortOrder()), forKey: "sortOrder")
        object.setValue(timestamp, forKey: "createdAt")
        object.setValue(timestamp, forKey: "updatedAt")

        try saveIfNeeded()
        return localID
    }

    func renameUserList(localID: String, name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            throw ContentLibraryStoreError.emptyListName
        }

        let list = try userList(localID: localID)
        list.setValue(trimmedName, forKey: "name")
        list.setValue(now(), forKey: "updatedAt")

        try saveIfNeeded()
    }

    func deleteUserList(localID: String) throws {
        let list = try userList(localID: localID)
        let itemRequest = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        itemRequest.predicate = NSPredicate(format: "listLocalID == %@", localID)
        for item in try context.fetch(itemRequest) {
            context.delete(item)
        }
        context.delete(list)

        try saveIfNeeded()
    }

    func removeListItem(localID: String) throws {
        let item = try userListItem(localID: localID)
        context.delete(item)
        try saveIfNeeded()
    }

    func moveUserList(localID: String, direction: ListMoveDirection) throws {
        _ = try userList(localID: localID)
        var lists = try allUserLists()
        guard let currentIndex = lists.firstIndex(where: { $0.stringValue(forKey: "localID") == localID }) else {
            throw ContentLibraryStoreError.listNotFound
        }

        let targetIndex: Int
        switch direction {
        case .earlier:
            targetIndex = currentIndex - 1
        case .later:
            targetIndex = currentIndex + 1
        }

        guard lists.indices.contains(targetIndex) else {
            return
        }

        lists.swapAt(currentIndex, targetIndex)
        try reindexSortOrder(objects: lists)
    }

    func moveListItem(localID: String, direction: ListMoveDirection) throws {
        let item = try userListItem(localID: localID)
        let listLocalID = item.stringValue(forKey: "listLocalID")
        var items = try userListItems(listLocalID: listLocalID)
        guard let currentIndex = items.firstIndex(where: { $0.stringValue(forKey: "localID") == localID }) else {
            throw ContentLibraryStoreError.listItemNotFound
        }

        let targetIndex: Int
        switch direction {
        case .earlier:
            targetIndex = currentIndex - 1
        case .later:
            targetIndex = currentIndex + 1
        }

        guard items.indices.contains(targetIndex) else {
            return
        }

        items.swapAt(currentIndex, targetIndex)
        try reindexSortOrder(objects: items)
    }

    func sortListItems(listLocalID: String, mode: ListItemSortMode) throws {
        _ = try userList(localID: listLocalID)
        let items = try userListItems(listLocalID: listLocalID)
        let metricsByLocalID = listItemSortMetrics(for: items)
        let sortedItems = items
            .sorted { lhs, rhs in
                compareListItems(lhs, rhs, mode: mode, metricsByLocalID: metricsByLocalID)
            }
        try reindexSortOrder(objects: sortedItems)
    }

    func setListMembership(itemLocalID: String, listLocalID: String, isIncluded: Bool) throws {
        let item = try trackedItem(localID: itemLocalID)
        _ = try userList(localID: listLocalID)

        if isIncluded {
            try upsertListMembership(item: item, listLocalID: listLocalID)
        } else {
            try removeListMembership(item: item, listLocalID: listLocalID)
        }

        try saveIfNeeded()
    }

    func removeFromLibrary(localID: String, kind: MediaKind) throws {
        let item = try trackedItem(localID: localID, kind: kind)
        let providerPredicate = providerIdentityPredicate(for: item)

        let listItemRequest = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        listItemRequest.predicate = providerPredicate.map { providerPredicate in
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "itemLocalID == %@", localID),
                providerPredicate
            ])
        } ?? NSPredicate(format: "itemLocalID == %@", localID)
        for listItem in try context.fetch(listItemRequest) {
            context.delete(listItem)
        }

        if kind == .show {
            let episodeRequest = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
            episodeRequest.predicate = NSPredicate(format: "showLocalID == %@", localID)
            for episode in try context.fetch(episodeRequest) {
                deleteMetadataRecords(kindRaw: "episode", localID: episode.stringValue(forKey: "localID"))
                context.delete(episode)
            }
        }

        deleteMetadataRecords(kindRaw: kind.rawValue, localID: localID)
        context.delete(item)
        try saveIfNeeded()
    }

    static func stableLocalID(for item: MediaSummary) -> String {
        stableLocalID(kind: item.kind, contentIDs: item.contentIDs, fallbackID: item.id)
    }

    static func stableLocalID(kind: MediaKind, contentIDs: ContentIDs, fallbackID: String) -> String {
        if let tvdbID = contentIDs.tvdbID {
            return "provider:\(kind.rawValue):tvdb:\(tvdbID)"
        }

        if let tmdbID = contentIDs.tmdbID {
            return "provider:\(kind.rawValue):tmdb:\(tmdbID)"
        }

        if let imdbID = contentIDs.imdbID, imdbID.isEmpty == false {
            return "provider:\(kind.rawValue):imdb:\(imdbID)"
        }

        return "provider:\(kind.rawValue):local:\(fallbackID)"
    }

    static func metadataCacheID(kindRaw: String, localID: String) -> String {
        "metadata:\(kindRaw):\(localID)"
    }

    private static let watchlistLocalID = "cinue:list:watchlist"

    private func userList(localID: String) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", localID)

        guard let list = try context.fetch(request).first else {
            throw ContentLibraryStoreError.listNotFound
        }

        return list
    }

    private func allUserLists() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        request.returnsObjectsAsFaults = false
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]
        return try context.fetch(request)
    }

    private func userListItem(localID: String) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", localID)

        guard let item = try context.fetch(request).first else {
            throw ContentLibraryStoreError.listItemNotFound
        }

        return item
    }

    private func userListItems(listLocalID: String) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "listLocalID == %@", listLocalID)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]
        return try context.fetch(request)
    }

    private func reindexSortOrder(objects: [NSManagedObject]) throws {
        let timestamp = now()
        for (index, object) in objects.enumerated() {
            object.setValue(Int32(index), forKey: "sortOrder")
            object.setValue(timestamp, forKey: "updatedAt")
        }
        try saveIfNeeded()
    }

    private func compareListItems(
        _ lhs: NSManagedObject,
        _ rhs: NSManagedObject,
        mode: ListItemSortMode,
        metricsByLocalID: [String: ListItemSortMetrics]
    ) -> Bool {
        let lhsMetrics = metricsByLocalID[lhs.stringValue(forKey: "localID")] ?? listItemSortMetrics(for: lhs)
        let rhsMetrics = metricsByLocalID[rhs.stringValue(forKey: "localID")] ?? listItemSortMetrics(for: rhs)

        switch mode {
        case .titleAscending:
            return localizedSort(lhsMetrics.title, rhsMetrics.title, lhs: lhs, rhs: rhs, ascending: true)
        case .titleDescending:
            return localizedSort(lhsMetrics.title, rhsMetrics.title, lhs: lhs, rhs: rhs, ascending: false)
        case .titleAscendingIgnoringArticles:
            return localizedSort(
                lhsMetrics.articleInsensitiveTitle,
                rhsMetrics.articleInsensitiveTitle,
                lhs: lhs,
                rhs: rhs,
                ascending: true,
                fallbackTitle: (lhsMetrics.title, rhsMetrics.title)
            )
        case .mediaKindThenTitle:
            if lhsMetrics.kindRaw != rhsMetrics.kindRaw {
                return lhsMetrics.kindRaw < rhsMetrics.kindRaw
            }
            return localizedSort(lhsMetrics.title, rhsMetrics.title, lhs: lhs, rhs: rhs, ascending: true)
        case .latestEpisode:
            return dateSort(
                lhsMetrics.latestEpisodeDate,
                rhsMetrics.latestEpisodeDate,
                lhs: lhs,
                rhs: rhs,
                lhsTitle: lhsMetrics.title,
                rhsTitle: rhsMetrics.title,
                ascending: false
            )
        case .oldestEpisode:
            return dateSort(
                lhsMetrics.oldestEpisodeDate,
                rhsMetrics.oldestEpisodeDate,
                lhs: lhs,
                rhs: rhs,
                lhsTitle: lhsMetrics.title,
                rhsTitle: rhsMetrics.title,
                ascending: true
            )
        case .lastWatched:
            return dateSort(
                lhsMetrics.lastWatchedAt,
                rhsMetrics.lastWatchedAt,
                lhs: lhs,
                rhs: rhs,
                lhsTitle: lhsMetrics.title,
                rhsTitle: rhsMetrics.title,
                ascending: false
            )
        case .leastRemainingEpisodes:
            switch (lhsMetrics.remainingEpisodeCount, rhsMetrics.remainingEpisodeCount) {
            case let (lhsCount?, rhsCount?) where lhsCount != rhsCount:
                return lhsCount < rhsCount
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return localizedSort(lhsMetrics.title, rhsMetrics.title, lhs: lhs, rhs: rhs, ascending: true)
            }
        }
    }

    private func localizedSort(
        _ lhsTitle: String,
        _ rhsTitle: String,
        lhs: NSManagedObject,
        rhs: NSManagedObject,
        ascending: Bool,
        fallbackTitle: (lhs: String, rhs: String)? = nil
    ) -> Bool {
        let comparison = lhsTitle.localizedStandardCompare(rhsTitle)
        if comparison == .orderedSame {
            if let fallbackTitle {
                let fallbackComparison = fallbackTitle.lhs.localizedStandardCompare(fallbackTitle.rhs)
                if fallbackComparison != .orderedSame {
                    return fallbackComparison == .orderedAscending
                }
            }

            return lhs.stringValue(forKey: "localID") < rhs.stringValue(forKey: "localID")
        }

        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func dateSort(
        _ lhsDate: Date?,
        _ rhsDate: Date?,
        lhs: NSManagedObject,
        rhs: NSManagedObject,
        lhsTitle: String,
        rhsTitle: String,
        ascending: Bool
    ) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return localizedSort(lhsTitle, rhsTitle, lhs: lhs, rhs: rhs, ascending: true)
        }
    }

    private func listItemSortMetrics(for listItems: [NSManagedObject]) -> [String: ListItemSortMetrics] {
        listItems.reduce(into: [:]) { result, item in
            let localID = item.stringValue(forKey: "localID")
            if localID.isEmpty == false {
                result[localID] = listItemSortMetrics(for: item)
            }
        }
    }

    private func listItemSortMetrics(for listItem: NSManagedObject) -> ListItemSortMetrics {
        let trackedItem = resolvedTrackedItem(for: listItem)
        let title = trackedItem?.stringValue(forKey: "sortTitle", fallback: trackedItem?.stringValue(forKey: "title") ?? "")
            ?? resolvedListItemTitle(listItem)
        let kindRaw = trackedItem?.stringValue(forKey: "kindRaw") ?? listItem.stringValue(forKey: "kindRaw")
        let showMetrics = trackedItem.flatMap { episodeMetrics(for: $0) }

        return ListItemSortMetrics(
            title: title,
            articleInsensitiveTitle: Self.articleInsensitiveTitle(title),
            kindRaw: kindRaw,
            latestEpisodeDate: showMetrics?.latestEpisodeDate,
            oldestEpisodeDate: showMetrics?.oldestEpisodeDate,
            lastWatchedAt: trackedItem?.value(forKey: "watchedAt") as? Date,
            remainingEpisodeCount: showMetrics?.remainingEpisodeCount
        )
    }

    private func episodeMetrics(for trackedItem: NSManagedObject) -> ListEpisodeSortMetrics? {
        guard trackedItem.stringValue(forKey: "kindRaw") == MediaKind.show.rawValue else {
            return nil
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "showLocalID == %@", trackedItem.stringValue(forKey: "localID"))
        let episodes = (try? context.fetch(request)) ?? []
        guard episodes.isEmpty == false else {
            return ListEpisodeSortMetrics(latestEpisodeDate: nil, oldestEpisodeDate: nil, remainingEpisodeCount: 0)
        }

        let releaseDates = episodeReleaseDates(for: episodes)
        let remaining = episodes.filter { episode in
            let statusRaw = episode.stringValue(forKey: "statusRaw")
            let watchCount = episode.intValue(forKey: "watchCount")
            let isSkipped = episode.boolValue(forKey: "isSkipped")
            return statusRaw != WatchStatus.watched.rawValue
                && statusRaw != WatchStatus.skipped.rawValue
                && watchCount == 0
                && isSkipped == false
        }
        .count

        return ListEpisodeSortMetrics(
            latestEpisodeDate: releaseDates.max(),
            oldestEpisodeDate: releaseDates.min(),
            remainingEpisodeCount: remaining
        )
    }

    private func episodeReleaseDates(for episodes: [NSManagedObject]) -> [Date] {
        let cacheIDs = episodes.flatMap { episode in
            let localID = episode.stringValue(forKey: "localID")
            return [
                "seriesguide:episode:\(localID)",
                ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: localID)
            ]
        }

        guard cacheIDs.isEmpty == false else {
            return []
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)
        return ((try? context.fetch(request)) ?? [])
            .compactMap { $0.value(forKey: "releaseDate") as? Date }
    }

    private static func articleInsensitiveTitle(_ title: String) -> String {
        let lowercased = title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        for article in ["the ", "a ", "an "] where lowercased.hasPrefix(article) {
            return String(lowercased.dropFirst(article.count))
        }

        return lowercased
    }

    private func resolvedListItemTitle(_ listItem: NSManagedObject) -> String {
        if let trackedItem = resolvedTrackedItem(for: listItem) {
            return trackedItem.stringValue(forKey: "sortTitle", fallback: trackedItem.stringValue(forKey: "title"))
        }

        return listItem.optionalStringValue(forKey: "externalID")
            ?? listItem.stringValue(forKey: "localID")
    }

    private func resolvedTrackedItem(for listItem: NSManagedObject) -> NSManagedObject? {
        if let itemLocalID = listItem.optionalStringValue(forKey: "itemLocalID") {
            let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "localID == %@", itemLocalID)
            if let item = try? context.fetch(request).first {
                return item
            }
        }

        let kindRaw = listItem.stringValue(forKey: "kindRaw")
        var predicates: [NSPredicate] = []
        if let tvdbID = listItem.optionalIntValue(forKey: "tvdbID") {
            predicates.append(NSPredicate(format: "tvdbID == %@", NSNumber(value: tvdbID)))
        }
        if let tmdbID = listItem.optionalIntValue(forKey: "tmdbID") {
            predicates.append(NSPredicate(format: "tmdbID == %@", NSNumber(value: tmdbID)))
        }
        if let externalID = listItem.optionalStringValue(forKey: "externalID"), let externalIntID = Int(externalID) {
            predicates.append(NSPredicate(format: "tvdbID == %@", NSNumber(value: externalIntID)))
            predicates.append(NSPredicate(format: "tmdbID == %@", NSNumber(value: externalIntID)))
        }

        guard predicates.isEmpty == false else {
            return nil
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "kindRaw == %@", kindRaw),
            NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        ])
        return try? context.fetch(request).first
    }

    private func trackedItem(localID: String, kind: MediaKind? = nil) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.fetchLimit = 1
        if let kind {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "localID == %@", localID),
                NSPredicate(format: "kindRaw == %@", kind.rawValue)
            ])
        } else {
            request.predicate = NSPredicate(format: "localID == %@", localID)
        }

        guard let item = try context.fetch(request).first else {
            throw ContentLibraryStoreError.itemNotFound
        }

        return item
    }

    private func nextListSortOrder() -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1
        let current = (try? context.fetch(request).first?.value(forKey: "sortOrder") as? NSNumber)?.intValue ?? -1
        return current + 1
    }

    private func existingTrackedItem(for item: MediaSummary) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "kindRaw == %@", item.kind.rawValue),
            identityPredicate(for: item, stableLocalID: Self.stableLocalID(for: item))
        ])

        return try context.fetch(request).first
    }

    private func identityPredicate(for item: MediaSummary, stableLocalID: String) -> NSPredicate {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "localID == %@", stableLocalID)
        ]

        if let tvdbID = item.contentIDs.tvdbID {
            predicates.append(NSPredicate(format: "tvdbID == %@", NSNumber(value: tvdbID)))
        }

        if let tmdbID = item.contentIDs.tmdbID {
            predicates.append(NSPredicate(format: "tmdbID == %@", NSNumber(value: tmdbID)))
        }

        if let imdbID = item.contentIDs.imdbID, imdbID.isEmpty == false {
            predicates.append(NSPredicate(format: "imdbID == %@", imdbID))
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    private func upsertListMembership(item: NSManagedObject, listLocalID: String) throws {
        let itemLocalID = item.stringValue(forKey: "localID")
        let localID = "cinue:listitem:\(listLocalID):\(itemLocalID)"
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", localID)
        let existing = try context.fetch(request).first
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "UserListItem", into: context)
        let timestamp = now()

        if existing == nil {
            object.setValue(localID, forKey: "localID")
            object.setValue(timestamp, forKey: "createdAt")
            object.setValue(Int32(nextListItemSortOrder(listLocalID: listLocalID)), forKey: "sortOrder")
        }

        object.setValue(listLocalID, forKey: "listLocalID")
        object.setValue(itemLocalID, forKey: "itemLocalID")
        object.setValue(providerExternalID(for: item), forKey: "externalID")
        object.setValue(item.stringValue(forKey: "kindRaw"), forKey: "kindRaw")
        object.setValue(item.value(forKey: "tvdbID"), forKey: "tvdbID")
        object.setValue(item.value(forKey: "tmdbID"), forKey: "tmdbID")
        object.setValue(timestamp, forKey: "updatedAt")
    }

    private func removeListMembership(item: NSManagedObject, listLocalID: String) throws {
        let itemLocalID = item.stringValue(forKey: "localID")
        var predicates: [NSPredicate] = [
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "listLocalID == %@", listLocalID),
                NSPredicate(format: "itemLocalID == %@", itemLocalID)
            ])
        ]

        if let providerPredicate = providerIdentityPredicate(for: item) {
            predicates.append(
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "listLocalID == %@", listLocalID),
                    providerPredicate
                ])
            )
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        for listItem in try context.fetch(request) {
            context.delete(listItem)
        }
    }

    private func nextListItemSortOrder(listLocalID: String) -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.predicate = NSPredicate(format: "listLocalID == %@", listLocalID)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: false)]
        request.fetchLimit = 1
        let current = (try? context.fetch(request).first?.value(forKey: "sortOrder") as? NSNumber)?.intValue ?? -1
        return current + 1
    }

    private func upsertWatchlist(timestamp: Date) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "localID == %@", Self.watchlistLocalID)
        let existing = try context.fetch(request).first
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "UserList", into: context)

        if existing == nil {
            object.setValue(Self.watchlistLocalID, forKey: "localID")
            object.setValue("Watchlist", forKey: "name")
            object.setValue(Int32(0), forKey: "sortOrder")
            object.setValue(timestamp, forKey: "createdAt")
        }

        object.setValue(timestamp, forKey: "updatedAt")
        return object
    }

    private func upsertMetadataRecord(for item: MediaSummary, localID: String, timestamp: Date) {
        let cacheID = Self.metadataCacheID(kindRaw: item.kind.rawValue, localID: localID)
        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "cacheID == %@", cacheID)
        let existing = try? context.fetch(request).first
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "MetadataRecord", into: context)

        object.setValue(cacheID, forKey: "cacheID")
        object.setValue(item.attribution.providerID.rawValue, forKey: "providerRaw")
        object.setValue(providerContentID(for: item), forKey: "providerContentID")
        object.setValue(item.kind.rawValue, forKey: "kindRaw")
        object.setValue(item.title, forKey: "title")
        object.setValue(item.overview, forKey: "overview")
        object.setValue(item.posterURL?.absoluteString, forKey: "posterURLString")
        object.setValue(item.backdropURL?.absoluteString, forKey: "backdropURLString")
        object.setValue(item.releaseDate, forKey: "releaseDate")
        object.setValue(sourceURLString(for: item), forKey: "sourceURLString")
        object.setValue(item.attribution.requiredText, forKey: "attributionText")
        object.setValue(timestamp, forKey: "fetchedAt")
        object.setValue(Calendar.current.date(byAdding: .month, value: 6, to: timestamp), forKey: "expiresAt")
    }

    private func providerContentID(for item: MediaSummary) -> String {
        if let tvdbID = item.contentIDs.tvdbID {
            return "tvdb:\(tvdbID)"
        }

        if let tmdbID = item.contentIDs.tmdbID {
            return "tmdb:\(tmdbID)"
        }

        if let imdbID = item.contentIDs.imdbID, imdbID.isEmpty == false {
            return "imdb:\(imdbID)"
        }

        return item.id
    }

    private func providerExternalID(for item: MediaSummary) -> String? {
        if let tvdbID = item.contentIDs.tvdbID {
            return "\(tvdbID)"
        }

        if let tmdbID = item.contentIDs.tmdbID {
            return "\(tmdbID)"
        }

        return item.contentIDs.imdbID
    }

    private func providerExternalID(for item: NSManagedObject) -> String? {
        if let tmdbID = item.value(forKey: "tmdbID") as? NSNumber {
            return "\(tmdbID.intValue)"
        }

        if let tvdbID = item.value(forKey: "tvdbID") as? NSNumber {
            return "\(tvdbID.intValue)"
        }

        return item.value(forKey: "imdbID") as? String
    }

    private func providerIdentityPredicate(for item: NSManagedObject) -> NSPredicate? {
        var predicates: [NSPredicate] = []
        let kindRaw = item.stringValue(forKey: "kindRaw")

        if let tvdbID = item.value(forKey: "tvdbID") as? NSNumber {
            predicates.append(
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "kindRaw == %@", kindRaw),
                    NSPredicate(format: "tvdbID == %@", tvdbID)
                ])
            )
        }

        if let tmdbID = item.value(forKey: "tmdbID") as? NSNumber {
            predicates.append(
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "kindRaw == %@", kindRaw),
                    NSPredicate(format: "tmdbID == %@", tmdbID)
                ])
            )
        }

        return predicates.isEmpty ? nil : NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    private func deleteMetadataRecords(kindRaw: String, localID: String) {
        let cacheIDs = [
            "seriesguide:\(kindRaw):\(localID)",
            Self.metadataCacheID(kindRaw: kindRaw, localID: localID)
        ]
        let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
        request.predicate = NSPredicate(format: "cacheID IN %@", cacheIDs)
        for metadata in (try? context.fetch(request)) ?? [] {
            context.delete(metadata)
        }
    }

    private func sourceURLString(for item: MediaSummary) -> String? {
        guard item.attribution.providerID == .tmdb, let tmdbID = item.contentIDs.tmdbID else {
            return nil
        }

        switch item.kind {
        case .show:
            return "https://www.themoviedb.org/tv/\(tmdbID)"
        case .movie:
            return "https://www.themoviedb.org/movie/\(tmdbID)"
        }
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}

enum ContentLibraryStoreError: Error {
    case emptyListName
    case listNotFound
    case listItemNotFound
    case itemNotFound
}

private struct ListItemSortMetrics {
    var title: String
    var articleInsensitiveTitle: String
    var kindRaw: String
    var latestEpisodeDate: Date?
    var oldestEpisodeDate: Date?
    var lastWatchedAt: Date?
    var remainingEpisodeCount: Int?
}

private struct ListEpisodeSortMetrics {
    var latestEpisodeDate: Date?
    var oldestEpisodeDate: Date?
    var remainingEpisodeCount: Int
}

private extension NSManagedObject {
    func stringValue(forKey key: String, fallback: String = "") -> String {
        value(forKey: key) as? String ?? fallback
    }

    func optionalStringValue(forKey key: String) -> String? {
        guard let value = value(forKey: key) as? String, value.isEmpty == false else {
            return nil
        }

        return value
    }

    func optionalIntValue(forKey key: String) -> Int? {
        if let number = value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return value(forKey: key) as? Int
    }

    func intValue(forKey key: String) -> Int {
        if let number = value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return value(forKey: key) as? Int ?? 0
    }

    func boolValue(forKey key: String) -> Bool {
        value(forKey: key) as? Bool ?? false
    }

    func setOptionalInt(_ value: Int?, forKey key: String) {
        if let value {
            setValue(value, forKey: key)
        } else {
            setValue(nil, forKey: key)
        }
    }
}
