import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct SampleLibraryStoreTests {
    private let entities = ["TrackedItem", "EpisodeState", "UserList", "UserListItem"]
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func addsUsefulPersistentDataAndRefusesRepeat() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let store = SampleLibraryStore(persistence: controller, now: { date })
        try store.addSamples()
        #expect(try fetch("TrackedItem", context).count == 4)
        #expect(try fetch("EpisodeState", context).count == 3)
        #expect(try fetch("UserList", context).count == 1)
        #expect(try fetch("UserListItem", context).count == 2)
        let dashboard = NowSnapshotBuilder(context: context, now: { date }).snapshot(
            trackedShows: try fetch("TrackedItem", context), episodeStates: try fetch("EpisodeState", context))
        #expect(dashboard.upNext.count == 1)
        #expect(dashboard.recentlyWatched.count == 1)
        #expect(dashboard.upcoming.count == 1)
        let showID = try #require(dashboard.upNext.first?.showLocalID)
        let builder = MediaDetailSnapshotBuilder(context: context)
        let show = try #require(builder.snapshot(localID: showID, kind: .show))
        #expect(show.episodes.count == 3)
        let trackedShow = try #require(fetch("TrackedItem", context).first {
            $0.value(forKey: "localID") as? String == showID
        })
        #expect(trackedShow.value(forKey: "statusRaw") as? String == WatchStatus.watching.rawValue)
        #expect((trackedShow.value(forKey: "watchCount") as? NSNumber)?.intValue == 1)
        #expect(trackedShow.value(forKey: "watchedAt") as? Date == date.addingTimeInterval(-86400 * 7))
        let episode = try #require(builder.episodeSnapshot(showLocalID: showID, season: 1, episode: 2))
        #expect(episode.localID == dashboard.upNext.first?.localID)
        #expect(episode.title == "Low Tide")
        #expect(episode.airDate == date.addingTimeInterval(-2 * 86400))
        #expect(!episode.isWatched)
        let lists = UserListSnapshotBuilder(context: context).snapshots(from: try fetch("UserList", context))
        #expect(lists.count == 1)
        #expect(lists.first?.resolvedItemCount == 2)
        #expect(Set(lists.first?.items.map(\.title) ?? []) == Set(["Lantern Harbor", "Paper Moon Station"]))
        let statistics = StatisticsSnapshotBuilder(context: context).snapshot(asOf: date)
        #expect(statistics.showsTotal == 2)
        #expect(statistics.moviesTotal == 2)
        #expect(statistics.watchedMovies == 1)
        #expect(statistics.watchedEpisodes == 1)
        #expect(statistics.watchedEpisodeMinutes == 42)
        #expect(statistics.watchedMovieMinutes == 96)
        #expect(statistics.watchlistMovieMinutes == 96)
        #expect(statistics.showsWithNextEpisodes == 1)
        try WatchStateStore(context: context).markEpisodeWatched(localID: episode.localID)
        let watched = try #require(builder.episodeSnapshot(showLocalID: showID, season: 1, episode: 2))
        #expect(watched.isWatched)
        #expect(StatisticsSnapshotBuilder(context: context).snapshot(asOf: date).watchedEpisodes == 2)
        #expect(throws: SampleLibraryStore.SampleError.self) { try store.addSamples() }
        let fresh = controller.container.newBackgroundContext()
        let persistedCount = try fresh.performAndWait { () throws -> Int in
            try fresh.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "TrackedItem"))
        }
        #expect(persistedCount == 4)
        for item in try fetch("TrackedItem", context) {
            #expect(item.value(forKey: "tmdbID") == nil)
            #expect(item.value(forKey: "tvdbID") == nil)
            #expect(item.value(forKey: "imdbID") == nil)
        }
    }

    @Test func sampleBackupRoundTripPreservesLocalIdentityAndWatchState() throws {
        let sourceSuite = "Cinue.SampleBackup.Source.\(UUID().uuidString)"
        let targetSuite = "Cinue.SampleBackup.Target.\(UUID().uuidString)"
        let sourceDefaults = try #require(UserDefaults(suiteName: sourceSuite))
        let targetDefaults = try #require(UserDefaults(suiteName: targetSuite))
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            targetDefaults.removePersistentDomain(forName: targetSuite)
        }
        let source = PersistenceController(inMemory: true)
        let sourceContext = source.container.viewContext
        try SampleLibraryStore(persistence: source, now: { date }).addSamples()
        let episodes = try fetch("EpisodeState", sourceContext)
        let episode = try #require(episodes.first { $0.value(forKey: "title") as? String == "Low Tide" })
        let episodeID = try #require(episode.value(forKey: "localID") as? String)
        try WatchStateStore(context: sourceContext, now: { date }).markEpisodeWatched(localID: episodeID)
        let data = try BackupService(persistence: source, userDefaults: sourceDefaults).exportCinueBackup()

        let target = PersistenceController(inMemory: true)
        _ = try BackupService(persistence: target, userDefaults: targetDefaults).importCinueBackup(data: data)
        let targetContext = target.container.viewContext
        for (entity, count) in [("TrackedItem", 4), ("EpisodeState", 3), ("UserList", 1), ("UserListItem", 2)] {
            let originals = try fetch(entity, sourceContext)
            let restored = try fetch(entity, targetContext)
            #expect(restored.count == count)
            #expect(Set(originals.compactMap { $0.value(forKey: "localID") as? String }) ==
                    Set(restored.compactMap { $0.value(forKey: "localID") as? String }))
        }
        let restoredEpisode = try #require(fetch("EpisodeState", targetContext).first {
            $0.value(forKey: "localID") as? String == episodeID
        })
        #expect(restoredEpisode.value(forKey: "statusRaw") as? String == WatchStatus.watched.rawValue)
        #expect((restoredEpisode.value(forKey: "watchCount") as? NSNumber)?.intValue == 1)
        let lists = UserListSnapshotBuilder(context: targetContext).snapshots(from: try fetch("UserList", targetContext))
        #expect(lists.first?.resolvedItemCount == 2)
        for item in try fetch("TrackedItem", targetContext) {
            #expect(item.value(forKey: "tmdbID") == nil)
            #expect(item.value(forKey: "tvdbID") == nil)
            #expect(item.value(forKey: "imdbID") == nil)
        }
    }

    @Test func reseedingPreservesOrphanMetadataAndUsesNewDates() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        try SampleLibraryStore(persistence: controller, now: { date }).addSamples()
        let oldMetadata = try fetch("MetadataRecord", context)
        let oldValues = oldMetadata.map { object in
            (object.objectID, object.value(forKey: "cacheID") as? String, object.value(forKey: "releaseDate") as? Date)
        }
        for entity in entities {
            for object in try fetch(entity, context) { context.delete(object) }
        }
        try context.save()

        let later = date.addingTimeInterval(90 * 86400)
        try SampleLibraryStore(persistence: controller, now: { later }).addSamples()
        let allMetadata = try fetch("MetadataRecord", context)
        let cacheIDs = allMetadata.compactMap { $0.value(forKey: "cacheID") as? String }
        #expect(allMetadata.count == 10)
        #expect(Set(cacheIDs).count == 10)
        for (objectID, cacheID, releaseDate) in oldValues {
            let object = try context.existingObject(with: objectID)
            #expect(object.value(forKey: "cacheID") as? String == cacheID)
            #expect(object.value(forKey: "releaseDate") as? Date == releaseDate)
        }
        let dashboard = NowSnapshotBuilder(context: context, now: { later }).snapshot(
            trackedShows: try fetch("TrackedItem", context), episodeStates: try fetch("EpisodeState", context))
        #expect(dashboard.upNext.first?.airDate == later.addingTimeInterval(-2 * 86400))
        #expect(dashboard.upcoming.first?.airDate == later.addingTimeInterval(5 * 86400))
    }

    @Test func refusesEachPendingCollectionWithoutChangingIt() throws {
        for entity in entities {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext
            let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            #expect(throws: SampleLibraryStore.SampleError.self) { try SampleLibraryStore(persistence: controller).addSamples() }
            #expect(context.insertedObjects.contains(object))
            #expect(context.insertedObjects.count == 1)
        }
    }

    @Test func refusesEachSavedCollection() throws {
        for entity in entities {
            let controller = PersistenceController(inMemory: true)
            let context = controller.container.viewContext
            let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            object.setValue("existing", forKey: "localID")
            object.setValue(date, forKey: "createdAt")
            object.setValue(date, forKey: "updatedAt")
            switch entity {
            case "TrackedItem":
                object.setValue("Existing", forKey: "title")
                object.setValue("show", forKey: "kindRaw")
            case "EpisodeState": object.setValue("orphan", forKey: "showLocalID")
            case "UserList": object.setValue("Existing", forKey: "name")
            case "UserListItem": object.setValue("orphan", forKey: "listLocalID")
            default: break
            }
            try context.save()
            #expect(throws: SampleLibraryStore.SampleError.self) { try SampleLibraryStore(persistence: controller).addSamples() }
            #expect(try fetch(entity, context).count == 1)
            #expect(!context.hasChanges)
        }
    }

    @Test func failedSaveRemovesAllSampleInserts() throws {
        struct Failure: Error {}
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let store = SampleLibraryStore(persistence: controller, now: { date }, save: { _ in throw Failure() })
        #expect(throws: Failure.self) { try store.addSamples() }
        for entity in entities + ["MetadataRecord"] { #expect(try fetch(entity, context).isEmpty) }
        #expect(!context.hasChanges)
    }

    @Test func refusesMovieOnlyLibrary() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let movie = NSEntityDescription.insertNewObject(forEntityName: "TrackedItem", into: context)
        movie.setValue("existing:movie", forKey: "localID")
        movie.setValue("Existing movie", forKey: "title")
        movie.setValue("movie", forKey: "kindRaw")
        movie.setValue(date, forKey: "createdAt")
        movie.setValue(date, forKey: "updatedAt")
        try context.save()
        #expect(throws: SampleLibraryStore.SampleError.self) {
            try SampleLibraryStore(persistence: controller).addSamples()
        }
        #expect(try fetch("TrackedItem", context).count == 1)
        #expect(movie.value(forKey: "title") as? String == "Existing movie")
        #expect(try fetch("EpisodeState", context).isEmpty)
    }

    @Test func pendingUnrelatedChangesArePreserved() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let setting = NSEntityDescription.insertNewObject(forEntityName: "ProviderSetting", into: context)
        #expect(throws: SampleLibraryStore.SampleError.self) { try SampleLibraryStore(persistence: controller).addSamples() }
        #expect(context.insertedObjects.contains(setting))
    }

    @Test func concurrentAttemptsProduceOneLibrary() async throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask { @MainActor in
                    do { try SampleLibraryStore(persistence: controller).addSamples(); return true }
                    catch { return false }
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try fetch("TrackedItem", context).count == 4)
    }

    @Test func activeBackgroundImportMakesSamplesDeclineWithoutChangingImport() async throws {
        let controller = PersistenceController(inMemory: true)
        let enteredSave = DispatchSemaphore(value: 0)
        let releaseSave = DispatchSemaphore(value: 0)
        let service = BackupService(persistence: controller, contextSave: { context in
            enteredSave.signal()
            releaseSave.wait()
            try context.save()
        })
        let data = Data("""
        [{"tmdb_id": 990000001, "title": "Signal Harbor", "seasons": []}]
        """.utf8)
        let importing = Task.detached {
            try service.importSeriesGuideShows(data: data)
        }
        let reachedSave = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: enteredSave.wait(timeout: .now() + 10) == .success)
            }
        }
        guard reachedSave else {
            releaseSave.signal()
            _ = try? await importing.value
            Issue.record("Import did not reach its save hook")
            return
        }
        do {
            try SampleLibraryStore(persistence: controller).addSamples()
            Issue.record("Sample creation should decline while import holds the coordinator")
        } catch SampleLibraryStore.SampleError.busy {
            // Expected: no waiting for the background transaction.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        releaseSave.signal()
        _ = try await importing.value
        let items = try fetch("TrackedItem", controller.container.viewContext)
        #expect(items.count == 1)
        #expect(items.first?.value(forKey: "title") as? String == "Signal Harbor")
        #expect(try fetch("UserList", controller.container.viewContext).isEmpty)
        #expect(throws: SampleLibraryStore.SampleError.self) {
            try SampleLibraryStore(persistence: controller).addSamples()
        }
    }

    private func fetch(_ entity: String, _ context: NSManagedObjectContext) throws -> [NSManagedObject] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
    }
}
