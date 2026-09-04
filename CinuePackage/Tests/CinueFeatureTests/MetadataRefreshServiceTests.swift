import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct MetadataRefreshServiceTests {
    @Test
    func refreshUpdatesShowProviderStatusAndAddsUpcomingEpisodeWithoutChangingWatchState() async throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let transport = RefreshTransport(response: tvDetailsResponse)
        let client = TMDBClient(apiKey: { "1234567890abcdef1234567890abcdef" }, transport: transport.data(for:))
        let service = MetadataRefreshService(
            persistence: controller,
            tmdbClient: client,
            now: Self.fixedDate,
            staleInterval: 0,
            maxItemsPerRun: 10
        )
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "status": "Ended",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "watched": true, "plays": 1 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))

        let summary = await service.refreshStaleMetadata(force: true)

        #expect(summary.refreshedItems == 1)
        #expect(summary.refreshedEpisodes == 1)
        #expect(summary.skippedFreshItems == 0)
        #expect(await transport.paths == ["/3/tv/68421"])

        let show = try fetchObject(in: controller, entityName: "TrackedItem", localID: "seriesguide:show:tvdb:332331")
        #expect((show.value(forKey: "watchCount") as? NSNumber)?.intValue == 1)
        #expect(show.value(forKey: "statusRaw") as? String == WatchStatus.watching.rawValue)

        let librarySnapshot = try #require(
            LibraryItemSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [show])
                .first
        )
        #expect(librarySnapshot.providerStatusLabel == "Continuing")

        let episode = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .episodeSnapshot(showLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 3)
        )
        #expect(episode.titleLine == "1x03 Fresh Upload")
        #expect(episode.isWatched == false)
        #expect(episode.dateLine != nil)

        let nowSnapshot = NowSnapshotBuilder(context: controller.container.viewContext, now: Self.fixedDate)
            .snapshot(trackedShows: [show], episodeStates: try fetchObjects(in: controller, entityName: "EpisodeState"))
        #expect(nowSnapshot.upcoming.map(\.titleLine).contains("1x03 Fresh Upload"))
    }

    @Test
    func appOpenRefreshRepairsFreshSeriesGuideArtworkWithProviderMetadata() async throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let transport = RefreshTransport(response: tvDetailsResponse)
        let client = TMDBClient(apiKey: { "1234567890abcdef1234567890abcdef" }, transport: transport.data(for:))
        let service = MetadataRefreshService(
            persistence: controller,
            tmdbClient: client,
            now: Self.fixedDate,
            staleInterval: 60 * 60 * 24,
            maxItemsPerRun: 10
        )
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "poster": "/altered-carbon.jpg",
            "status": "Continuing",
            "seasons": []
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))

        let summary = await service.refreshStaleMetadata(force: false)

        #expect(summary.refreshedItems == 1)
        #expect(summary.skippedFreshItems == 0)
        #expect(await transport.paths == ["/3/tv/68421"])

        let show = try fetchObject(in: controller, entityName: "TrackedItem", localID: "seriesguide:show:tvdb:332331")
        let snapshot = try #require(
            LibraryItemSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [show])
                .first
        )
        #expect(snapshot.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    @Test
    func appOpenRefreshSkipsFreshProviderMetadata() async throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let transport = RefreshTransport(response: tvDetailsResponse)
        let client = TMDBClient(apiKey: { "1234567890abcdef1234567890abcdef" }, transport: transport.data(for:))
        let service = MetadataRefreshService(
            persistence: controller,
            tmdbClient: client,
            now: Self.fixedDate,
            staleInterval: 60 * 60 * 24,
            maxItemsPerRun: 10
        )
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "status": "Continuing",
            "seasons": []
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))
        _ = await service.refreshStaleMetadata(force: true)
        await transport.resetPaths()

        let summary = await service.refreshStaleMetadata(force: false)

        #expect(summary.refreshedItems == 0)
        #expect(summary.skippedFreshItems == 1)
        #expect(await transport.paths.isEmpty)
    }

    @Test
    func refreshWritesProviderCacheExpiry() async throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let transport = RefreshTransport(response: tvDetailsResponse)
        let client = TMDBClient(apiKey: { "1234567890abcdef1234567890abcdef" }, transport: transport.data(for:))
        let service = MetadataRefreshService(
            persistence: controller,
            tmdbClient: client,
            now: Self.fixedDate,
            staleInterval: 60 * 60 * 24,
            maxItemsPerRun: 10
        )
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "status": "Continuing",
            "seasons": []
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))

        _ = await service.refreshStaleMetadata(force: true)

        let metadata = try fetchObject(
            in: controller,
            entityName: "MetadataRecord",
            key: "cacheID",
            value: "seriesguide:show:seriesguide:show:tvdb:332331"
        )
        #expect(metadata.value(forKey: "providerRaw") as? String == MetadataProviderID.tmdb.rawValue)
        #expect(metadata.value(forKey: "fetchedAt") as? Date == Self.fixedDate())
        #expect(
            metadata.value(forKey: "expiresAt") as? Date
                == Calendar.current.date(byAdding: .month, value: 6, to: Self.fixedDate())
        )
    }

    @Test
    func refreshSingleItemOnlyRequestsThatItem() async throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let transport = RefreshTransport(response: tvDetailsResponse)
        let client = TMDBClient(apiKey: { "1234567890abcdef1234567890abcdef" }, transport: transport.data(for:))
        let service = MetadataRefreshService(
            persistence: controller,
            tmdbClient: client,
            now: Self.fixedDate,
            staleInterval: 60 * 60 * 24,
            maxItemsPerRun: 10
        )
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": []
          },
          {
            "tmdb_id": 95396,
            "tvdb_id": 371980,
            "title": "Severance",
            "seasons": []
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))

        let summary = await service.refreshMetadata(localID: "seriesguide:show:tvdb:332331", kind: .show)

        #expect(summary.refreshedItems == 1)
        #expect(summary.failedItems == 0)
        #expect(await transport.paths == ["/3/tv/68421"])
    }

    @Test
    func refreshSingleItemReportsProviderFailureReason() async throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { request in
                (
                    Data(),
                    HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                )
            }
        )
        let service = MetadataRefreshService(
            persistence: controller,
            tmdbClient: client,
            now: Self.fixedDate,
            staleInterval: 0,
            maxItemsPerRun: 10
        )
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": []
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))

        let summary = await service.refreshMetadata(localID: "seriesguide:show:tvdb:332331", kind: .show)

        #expect(summary.refreshedItems == 0)
        #expect(summary.failedItems == 1)
        #expect(summary.failureReason == .rateLimited)
    }

    @Test
    func librarySnapshotShowsImportedSeriesStatus() throws {
        let controller = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: controller, now: Self.fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "status": "Canceled",
            "seasons": []
          }
        ]
        """
        _ = try backupService.importSeriesGuideShows(data: Data(json.utf8))

        let show = try fetchObject(in: controller, entityName: "TrackedItem", localID: "seriesguide:show:tvdb:332331")
        let snapshot = try #require(
            LibraryItemSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [show])
                .first
        )

        #expect(snapshot.providerStatusLabel == "Cancelled")
        #expect(snapshot.accessibilityLabel.contains("Cancelled"))
    }

    private var tvDetailsResponse: Data {
        """
        {
          "id": 68421,
          "name": "Altered Carbon",
          "overview": "A stack returns.",
          "first_air_date": "2018-02-02",
          "poster_path": "/poster.jpg",
          "backdrop_path": "/backdrop.jpg",
          "status": "Returning Series",
          "next_episode_to_air": {
            "id": 1401625,
            "name": "Fresh Upload",
            "overview": "A new case arrives.",
            "air_date": "2026-05-01",
            "season_number": 1,
            "episode_number": 3,
            "still_path": "/episode.jpg"
          }
        }
        """.data(using: .utf8)!
    }

    nonisolated private static func fixedDate() -> Date {
        Date(timeIntervalSince1970: 1_777_000_000)
    }
}

private actor RefreshTransport {
    private let response: Data
    private(set) var paths: [String] = []

    init(response: Data) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        paths.append(request.url?.path ?? "")
        return (
            response,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    func resetPaths() {
        paths.removeAll()
    }
}

@MainActor
private func fetchObject(in controller: PersistenceController, entityName: String, localID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.predicate = NSPredicate(format: "localID == %@", localID)
    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func fetchObject(
    in controller: PersistenceController,
    entityName: String,
    key: String,
    value: String
) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.predicate = NSPredicate(format: "%K == %@", key, value)
    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func fetchObjects(in controller: PersistenceController, entityName: String) throws -> [NSManagedObject] {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    return try controller.container.viewContext.fetch(request)
}
