import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct UserListSnapshotTests {
    @Test
    func snapshotsResolveSeriesGuideListItemsToLibraryRows() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let showJSON = """
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
        let listJSON = """
        [
          {
            "items": [
              { "externalId": "68421", "list_item_id": "68421-firstlist", "tvdb_id": 0, "type": "tmdb-show" }
            ],
            "list_id": "First%20list",
            "name": "First list",
            "order": 0
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(showJSON.utf8))
        _ = try service.importBackup(data: Data(listJSON.utf8))

        let list = try fetchObject(in: controller, entityName: "UserList", localID: "seriesguide:list:First%20list")
        let snapshot = try #require(
            UserListSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [list])
                .first
        )
        let item = try #require(snapshot.items.first)

        #expect(snapshot.name == "First list")
        #expect(snapshot.itemCount == 1)
        #expect(snapshot.resolvedItemCount == 1)
        #expect(snapshot.subtitle == "1 item")
        #expect(item.title == "Altered Carbon")
        #expect(item.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(item.detailLine == "1 of 2 episodes watched")
        #expect(item.accessibilityLabel.contains("332331") == false)
        #expect(item.accessibilityLabel.contains("68421") == false)
        #expect(item.accessibilityLabel.contains("TMDB") == false)
        #expect(item.accessibilityLabel.contains("TVDB") == false)
    }

    @Test
    func snapshotsKeepEmptyImportedListsVisible() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "items": [],
            "list_id": "Empty",
            "name": "Empty",
            "order": 0
          }
        ]
        """

        _ = try service.importBackup(data: Data(json.utf8))

        let list = try fetchObject(in: controller, entityName: "UserList", localID: "seriesguide:list:Empty")
        let snapshot = try #require(
            UserListSnapshotBuilder(context: controller.container.viewContext)
                .snapshots(from: [list])
                .first
        )

        #expect(snapshot.name == "Empty")
        #expect(snapshot.itemCount == 0)
        #expect(snapshot.resolvedItemCount == 0)
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.subtitle == "No items")
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
