import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct LibraryItemSnapshotTests {
    @Test
    func snapshotsUseImportedPosterAndEpisodeProgressWithoutProviderIDs() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "poster": "/poster.jpg",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "watched": true, "plays": 1 },
                  { "tmdb_id": 1401624, "episode": 2, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let item = try fetchTrackedItem(in: controller, localID: "seriesguide:show:tvdb:332331")
        let snapshots = LibraryItemSnapshotBuilder(context: controller.container.viewContext)
            .snapshots(from: [item])

        let snapshot = try #require(snapshots.first)
        #expect(snapshot.title == "Altered Carbon")
        #expect(snapshot.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(snapshot.statusLabel == "Watching")
        #expect(snapshot.detailLine == "1 of 2 episodes watched")
        #expect(snapshot.accessibilityLabel.contains("332331") == false)
        #expect(snapshot.accessibilityLabel.contains("68421") == false)
        #expect(snapshot.accessibilityLabel.contains("TMDB") == false)
        #expect(snapshot.accessibilityLabel.contains("TVDB") == false)
    }

    @Test
    func movieSnapshotsUseWatchStatusInsteadOfProviderIDs() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 19913,
            "imdb_id": "tt1022603",
            "title": "(500) Days of Summer",
            "watched": true,
            "plays": 2,
            "poster": "/movie.jpg"
          }
        ]
        """

        _ = try service.importBackup(data: Data(json.utf8))
        let item = try fetchTrackedItem(in: controller, localID: "seriesguide:movie:tmdb:19913")
        let snapshot = try #require(
            LibraryItemSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [item])
                .first
        )

        #expect(snapshot.kind == .movie)
        #expect(snapshot.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/movie.jpg")
        #expect(snapshot.statusLabel == "Watched")
        #expect(snapshot.detailLine == "2 plays")
        #expect(snapshot.accessibilityLabel.contains("19913") == false)
        #expect(snapshot.accessibilityLabel.contains("tt1022603") == false)
    }

    @Test
    func snapshotsExposeHiddenStateForLibraryRecovery() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "hidden": true,
            "seasons": []
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let item = try fetchTrackedItem(in: controller, localID: "seriesguide:show:tvdb:332331")
        let snapshot = try #require(
            LibraryItemSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [item])
                .first
        )

        #expect(snapshot.isHidden)
        #expect(snapshot.accessibilityLabel.contains("Hidden") == true)
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
