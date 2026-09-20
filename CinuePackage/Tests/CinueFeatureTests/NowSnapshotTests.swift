import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct NowSnapshotTests {
    @Test
    func snapshotBuildsUpNextHistoryRecentAndUpcomingFromImportedEpisodes() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "poster": "/poster.jpg",
            "last_watched_ms": 1700000000000,
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "first_aired": 1699900000000, "watched": true, "plays": 1 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "first_aired": 1700100000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 1401625, "episode": 3, "title": "Future Episode", "first_aired": 1893456000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let snapshot = NowSnapshotBuilder(
            context: controller.container.viewContext,
            now: { Date(timeIntervalSince1970: 1_700_200_000) }
        )
        .snapshot(
            trackedShows: try fetchObjects(in: controller, entityName: "TrackedItem"),
            episodeStates: try fetchObjects(in: controller, entityName: "EpisodeState")
        )

        #expect(snapshot.upNext.map(\.titleLine) == ["1x02 Fallen Angel"])
        #expect(snapshot.recentlyWatched.map(\.titleLine) == ["1x01 Out of the Past"])
        #expect(snapshot.recentlyAired.map(\.titleLine) == ["1x02 Fallen Angel"])
        #expect(snapshot.upcoming.map(\.titleLine) == ["1x03 Future Episode"])
        #expect(snapshot.upNext.first?.showPosterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(snapshot.upNext.first?.accessibilityLabel.contains("332331") == false)
        #expect(snapshot.upNext.first?.accessibilityLabel.contains("68421") == false)
    }

    @Test
    func upNextExcludesFutureEpisodes() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 1000,
            "tvdb_id": 100,
            "title": "Released Show",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 10001, "episode": 1, "title": "Released Episode", "first_aired": 1700000000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          },
          {
            "tmdb_id": 2000,
            "tvdb_id": 200,
            "title": "Future Show",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 20001, "episode": 1, "title": "Future Episode", "first_aired": 1893456000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let snapshot = NowSnapshotBuilder(
            context: controller.container.viewContext,
            now: { Date(timeIntervalSince1970: 1_700_600_000) }
        )
        .snapshot(
            trackedShows: try fetchObjects(in: controller, entityName: "TrackedItem"),
            episodeStates: try fetchObjects(in: controller, entityName: "EpisodeState")
        )

        #expect(snapshot.upNext.map(\.showTitle) == ["Released Show"])
        #expect(snapshot.upcoming.map(\.showTitle) == ["Future Show"])
    }

    @Test
    func upNextSortsShowsByMostRecentReleaseDate() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 1000,
            "tvdb_id": 100,
            "title": "Alpha Show",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 10001, "episode": 1, "title": "Older Pilot", "first_aired": 1700000000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          },
          {
            "tmdb_id": 2000,
            "tvdb_id": 200,
            "title": "Zulu Show",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 20001, "episode": 1, "title": "Recent Pilot", "first_aired": 1700500000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let snapshot = NowSnapshotBuilder(
            context: controller.container.viewContext,
            now: { Date(timeIntervalSince1970: 1_700_600_000) }
        )
        .snapshot(
            trackedShows: try fetchObjects(in: controller, entityName: "TrackedItem"),
            episodeStates: try fetchObjects(in: controller, entityName: "EpisodeState")
        )

        #expect(snapshot.upNext.map(\.showTitle) == ["Zulu Show", "Alpha Show"])
        #expect(snapshot.upNext.map(\.titleLine) == ["1x01 Recent Pilot", "1x01 Older Pilot"])
    }

    @Test
    func markingEpisodeWatchedUpdatesNowAndShowProgress() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "last_watched_ms": 1700000000000,
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "watched": true, "plays": 2 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))

        try WatchStateStore(
            context: controller.container.viewContext,
            now: { Date(timeIntervalSince1970: 1_700_300_000) }
        )
        .markEpisodeWatched(localID: "seriesguide:episode:tmdb:1401624")

        let episode = try fetchObject(in: controller, entityName: "EpisodeState", localID: "seriesguide:episode:tmdb:1401624")
        #expect(episode.value(forKey: "statusRaw") as? String == "watched")
        #expect((episode.value(forKey: "watchCount") as? NSNumber)?.intValue == 1)

        let show = try fetchObject(in: controller, entityName: "TrackedItem", localID: "seriesguide:show:tvdb:332331")
        #expect((show.value(forKey: "watchCount") as? NSNumber)?.intValue == 3)
        #expect(show.value(forKey: "statusRaw") as? String == "watched")

        let snapshot = NowSnapshotBuilder(context: controller.container.viewContext)
            .snapshot(
                trackedShows: try fetchObjects(in: controller, entityName: "TrackedItem"),
                episodeStates: try fetchObjects(in: controller, entityName: "EpisodeState")
            )

        #expect(snapshot.upNext.isEmpty)
        #expect(snapshot.recentlyWatched.map(\.titleLine).contains("1x02 Fallen Angel"))
    }

    @Test
    func episodeSkipCollectAndUnwatchActionsUpdateState() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let store = WatchStateStore(context: controller.container.viewContext, now: fixedDate)

        try store.toggleEpisodeSkipped(localID: "seriesguide:episode:tmdb:1401624")
        var episode = try fetchObject(in: controller, entityName: "EpisodeState", localID: "seriesguide:episode:tmdb:1401624")
        #expect(episode.value(forKey: "statusRaw") as? String == "skipped")
        #expect(episode.value(forKey: "isSkipped") as? Bool == true)

        try store.toggleEpisodeCollected(localID: "seriesguide:episode:tmdb:1401624")
        episode = try fetchObject(in: controller, entityName: "EpisodeState", localID: "seriesguide:episode:tmdb:1401624")
        #expect(episode.value(forKey: "isCollected") as? Bool == true)

        try store.markEpisodeWatched(localID: "seriesguide:episode:tmdb:1401624")
        try store.markEpisodeUnwatched(localID: "seriesguide:episode:tmdb:1401624")
        episode = try fetchObject(in: controller, entityName: "EpisodeState", localID: "seriesguide:episode:tmdb:1401624")
        #expect(episode.value(forKey: "statusRaw") as? String == "unwatched")
        #expect((episode.value(forKey: "watchCount") as? NSNumber)?.intValue == 0)
        #expect(episode.value(forKey: "watchedAt") == nil)
        #expect(episode.value(forKey: "isSkipped") as? Bool == false)
        #expect(episode.value(forKey: "isCollected") as? Bool == true)
    }
}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private func fetchObject(in controller: PersistenceController, entityName: String, localID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.predicate = NSPredicate(format: "localID == %@", localID)

    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func fetchObjects(in controller: PersistenceController, entityName: String) throws -> [NSManagedObject] {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    return try controller.container.viewContext.fetch(request)
}
