import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct StatisticsSnapshotTests {
    @Test
    func syntheticSeriesGuideFixturesDriveStatisticsSnapshot() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        _ = try service.importBackup(data: seriesGuideFixtureData(.shows))
        _ = try service.importBackup(data: seriesGuideFixtureData(.movies))

        let snapshot = StatisticsSnapshotBuilder(
            context: controller.container.viewContext
        ).snapshot()

        #expect(snapshot.showsTotal == 2)
        #expect(snapshot.showsWithNextEpisodes == 1)
        #expect(snapshot.continuingShows == 1)
        #expect(snapshot.finishedShows == 1)
        #expect(snapshot.episodesTotal == 4)
        #expect(snapshot.watchedEpisodes == 3)
        #expect(snapshot.watchedEpisodeMinutes == 102)
        #expect(snapshot.moviesTotal == 2)
        #expect(snapshot.watchedMovies == 1)
        #expect(snapshot.watchedMovieMinutes == 110)
        #expect(snapshot.watchlistMovies == 1)
        #expect(snapshot.watchlistMovieMinutes == 95)
        #expect(snapshot.collectionMovies == 1)
        #expect(snapshot.collectionMovieMinutes == 110)
    }

    @Test
    func releasedNextEpisodeCountExcludesHiddenAndUntrackedShows() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        [
          {
            "tmdb_id": 1,
            "tvdb_id": 1,
            "title": "Visible Show",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 11, "episode": 1, "title": "Visible Episode", "first_aired": 1600000000000, "watched": false, "plays": 0 }
              ] }
            ]
          },
          {
            "tmdb_id": 2,
            "tvdb_id": 2,
            "title": "Hidden Show",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 21, "episode": 1, "title": "Hidden Episode", "first_aired": 1600000000000, "watched": false, "plays": 0 }
              ] }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let context = controller.container.viewContext
        let hiddenShow = try fetchTrackedItem(in: controller, localID: "seriesguide:show:tvdb:2")
        hiddenShow.setValue(true, forKey: "isHidden")
        insertUntrackedReleasedEpisode(in: context, asOf: asOf)
        try context.save()

        let snapshot = StatisticsSnapshotBuilder(context: context).snapshot(asOf: asOf)

        #expect(snapshot.showsTotal == 1)
        #expect(snapshot.showsWithNextEpisodes == 1)
        #expect(snapshot.showsWithNextEpisodes <= snapshot.showsTotal)
    }

    @Test
    func releasedNextEpisodeCountUsesDatedFallbackMetadataWhenPrimaryIsUndated() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let episodeLocalID = "seriesguide:episode:tmdb:11"
        let json = """
        [
          {
            "tmdb_id": 1,
            "tvdb_id": 1,
            "title": "Fallback Metadata Show",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 11, "episode": 1, "title": "Fallback Episode", "watched": false, "plays": 0 }
              ] }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let context = controller.container.viewContext
        let primary = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:episode:\(episodeLocalID)")
        #expect(primary.value(forKey: "releaseDate") as? Date == nil)
        insertEpisodeMetadata(
            in: context,
            cacheID: ContentLibraryStore.metadataCacheID(kindRaw: "episode", localID: episodeLocalID),
            releaseDate: asOf
        )
        try context.save()

        let snapshot = StatisticsSnapshotBuilder(context: context).snapshot(asOf: asOf)

        #expect(snapshot.showsWithNextEpisodes == 1)
    }

    @Test
    func releasedNextEpisodeCountUsesEpisodeAvailabilityInsteadOfShowStatus() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        [
          {
            "tmdb_id": 1,
            "tvdb_id": 1,
            "title": "Continuing but Watched",
            "status": "Continuing",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 11, "episode": 1, "title": "Watched", "first_aired": 1600000000000, "watched": true, "plays": 1 }
              ] }
            ]
          },
          {
            "tmdb_id": 2,
            "tvdb_id": 2,
            "title": "Ended with Next",
            "status": "Ended",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 21, "episode": 1, "title": "Released", "first_aired": 1600000000000, "watched": false, "plays": 0 }
              ] }
            ]
          },
          {
            "tmdb_id": 3,
            "tvdb_id": 3,
            "title": "Unknown with One Next",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 31, "episode": 1, "title": "Released", "first_aired": 1600000000000, "watched": false, "plays": 0 },
                { "tmdb_id": 32, "episode": 2, "title": "Exactly Now", "first_aired": 1700000000000, "watched": false, "plays": 0 },
                { "tmdb_id": 33, "episode": 3, "title": "Future", "first_aired": 1800000000000, "watched": false, "plays": 0 },
                { "tmdb_id": 34, "episode": 4, "title": "Undated", "watched": false, "plays": 0 },
                { "tmdb_id": 35, "episode": 5, "title": "Watched", "first_aired": 1600000000000, "watched": true, "plays": 1 },
                { "tmdb_id": 36, "episode": 6, "title": "Skipped", "first_aired": 1600000000000, "watched": false, "plays": 0, "skipped": true }
              ] }
            ]
          },
          {
            "tmdb_id": 4,
            "tvdb_id": 4,
            "title": "Equality Only",
            "seasons": [
              { "season": 1, "episodes": [
                { "tmdb_id": 41, "episode": 1, "title": "Exactly Now", "first_aired": 1700000000000, "watched": false, "plays": 0 }
              ] }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let snapshot = StatisticsSnapshotBuilder(context: controller.container.viewContext).snapshot(asOf: asOf)

        #expect(snapshot.continuingShows == 1)
        #expect(snapshot.showsWithNextEpisodes == 3)
    }
}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private func fetchTrackedItem(in controller: PersistenceController, localID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
    request.predicate = NSPredicate(format: "localID == %@", localID)

    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func fetchMetadataRecord(in controller: PersistenceController, cacheID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
    request.predicate = NSPredicate(format: "cacheID == %@", cacheID)

    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func insertUntrackedReleasedEpisode(in context: NSManagedObjectContext, asOf: Date) {
    let localID = "test:episode:untracked"
    let episode = NSEntityDescription.insertNewObject(forEntityName: "EpisodeState", into: context)
    episode.setValue(asOf, forKey: "createdAt")
    episode.setValue(asOf, forKey: "updatedAt")
    episode.setValue(localID, forKey: "localID")
    episode.setValue("test:show:untracked", forKey: "showLocalID")
    episode.setValue(1, forKey: "seasonNumber")
    episode.setValue(1, forKey: "episodeNumber")
    episode.setValue("unwatched", forKey: "statusRaw")
    episode.setValue(0, forKey: "watchCount")
    episode.setValue(false, forKey: "isSkipped")
    episode.setValue(false, forKey: "isCollected")
    episode.setValue("Untracked Episode", forKey: "title")
    insertEpisodeMetadata(
        in: context,
        cacheID: "seriesguide:episode:\(localID)",
        releaseDate: asOf
    )
}

@MainActor
private func insertEpisodeMetadata(in context: NSManagedObjectContext, cacheID: String, releaseDate: Date?) {
    let metadata = NSEntityDescription.insertNewObject(forEntityName: "MetadataRecord", into: context)
    metadata.setValue(cacheID, forKey: "cacheID")
    metadata.setValue("episode", forKey: "kindRaw")
    metadata.setValue("test", forKey: "providerRaw")
    metadata.setValue(cacheID, forKey: "providerContentID")
    metadata.setValue("Test Episode", forKey: "title")
    metadata.setValue(fixedDate(), forKey: "fetchedAt")
    metadata.setValue(releaseDate, forKey: "releaseDate")
}
