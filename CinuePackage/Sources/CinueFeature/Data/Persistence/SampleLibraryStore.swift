import CoreData
import Foundation

@MainActor
struct SampleLibraryStore {
    enum SampleError: Error {
        case libraryNotEmpty
        case busy
    }

    let persistence: PersistenceController
    var context: NSManagedObjectContext { persistence.container.viewContext }
    var now: () -> Date = Date.init
    var save: (NSManagedObjectContext) throws -> Void = { try $0.save() }

    func addSamples() throws {
        guard try persistence.mutationCoordinator.tryWithLock({ try insertSamples() }) != nil else {
            throw SampleError.busy
        }
    }

    private func insertSamples() throws {
        // A dirty context can contain unsaved inserts, updates, or deletes. Refuse
        // rather than saving or rolling back changes belonging to another feature.
        guard !context.hasChanges else { throw SampleError.libraryNotEmpty }
        for entity in ["TrackedItem", "EpisodeState", "UserList", "UserListItem"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.fetchLimit = 1
            guard try context.fetch(request).isEmpty else { throw SampleError.libraryNotEmpty }
        }

        let timestamp = now()
        let namespace = "sample:\(UUID().uuidString)"
        func make(_ entity: String, _ values: [String: Any]) {
            let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            for (key, value) in values { object.setValue(value, forKey: key) }
        }
        let showID = "\(namespace):show:lantern-harbor"
        let movieID = "\(namespace):movie:paper-moon"
        for (id, title, kind, favorite, watched) in [
            (showID, "Lantern Harbor", "show", true, false),
            ("\(namespace):show:the-glass-garden", "The Glass Garden", "show", false, false),
            (movieID, "Paper Moon Station", "movie", true, true),
            ("\(namespace):movie:the-last-kite", "The Last Kite", "movie", false, false)
        ] {
            var values: [String: Any] = ["localID": id, "title": title, "sortTitle": title.lowercased(), "kindRaw": kind,
                "createdAt": timestamp, "updatedAt": timestamp, "statusRaw": watched ? "watched" : "unwatched",
                "watchCount": watched ? 1 : 0, "isFavorite": favorite]
            if watched { values["watchedAt"] = timestamp.addingTimeInterval(-86400 * 4) }
            if id == showID {
                values["statusRaw"] = WatchStatus.watching.rawValue
                values["watchCount"] = 1
                values["watchedAt"] = timestamp.addingTimeInterval(-86400 * 7)
            }
            make("TrackedItem", values)
        }
        // Insights reads runtimes from the same cached metadata representation
        // used by imported shows and movies.
        for (id, title, kind, payload) in [
            (showID, "Lantern Harbor", "show", #"{"runtime":42}"#),
            (movieID, "Paper Moon Station", "movie", #"{"runtime_min":96}"#)
        ] {
            make("MetadataRecord", ["cacheID": ContentLibraryStore.metadataCacheID(kindRaw: kind, localID: id),
                "kindRaw": kind, "providerRaw": "local", "providerContentID": id, "title": title,
                "fetchedAt": timestamp, "rawJSON": Data(payload.utf8)])
        }
        for (number, title, days, watched) in [(1, "The Beacon", -10, true), (2, "Low Tide", -2, false), (3, "The Crossing", 5, false)] {
            let id = "\(namespace):episode:lantern-harbor:\(number)"
            var values: [String: Any] = ["localID": id, "showLocalID": showID, "title": title, "seasonNumber": 1,
                "episodeNumber": number, "createdAt": timestamp, "updatedAt": timestamp,
                "statusRaw": watched ? "watched" : "unwatched", "watchCount": watched ? 1 : 0]
            if watched { values["watchedAt"] = timestamp.addingTimeInterval(-86400 * 7) }
            make("EpisodeState", values)
            make("MetadataRecord", ["cacheID": ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: id),
                "kindRaw": "episode", "providerRaw": "local", "providerContentID": id, "title": title,
                "fetchedAt": timestamp, "releaseDate": timestamp.addingTimeInterval(Double(days) * 86400)])
        }
        let listID = "\(namespace):list:weekend"
        make("UserList", ["localID": listID, "name": "Weekend picks", "createdAt": timestamp, "updatedAt": timestamp])
        for (index, item) in [(showID, "show"), (movieID, "movie")].enumerated() {
            make("UserListItem", ["localID": "\(namespace):listitem:\(index)", "listLocalID": listID,
                "itemLocalID": item.0, "kindRaw": item.1, "sortOrder": index, "createdAt": timestamp, "updatedAt": timestamp])
        }
        do {
            try save(context)
        } catch {
            // The context was clean before this synchronous, main-actor mutation,
            // so rollback can only discard changes made by this operation.
            context.rollback()
            throw error
        }
    }
}
