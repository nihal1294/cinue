import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct ListManagementTests {
    @Test
    func createRenameAndDeleteListUpdatesLocalLists() throws {
        let controller = PersistenceController(inMemory: true)
        let store = ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)

        let localID = try store.createUserList(name: "Weekend")
        var list = try fetchObject(in: controller, entityName: "UserList", localID: localID)
        #expect(list.value(forKey: "name") as? String == "Weekend")

        try store.renameUserList(localID: localID, name: "Awards")
        list = try fetchObject(in: controller, entityName: "UserList", localID: localID)
        #expect(list.value(forKey: "name") as? String == "Awards")

        try store.deleteUserList(localID: localID)
        #expect(try entityCount(in: controller, entityName: "UserList") == 0)
    }

    @Test
    func reorderListsUpdatesSortOrder() throws {
        let controller = PersistenceController(inMemory: true)
        let store = ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)

        let weekend = try store.createUserList(name: "Weekend")
        let awards = try store.createUserList(name: "Awards")
        let backlog = try store.createUserList(name: "Backlog")

        try store.moveUserList(localID: backlog, direction: .earlier)
        #expect(try orderedListNames(in: controller) == ["Weekend", "Backlog", "Awards"])

        try store.moveUserList(localID: weekend, direction: .later)
        #expect(try orderedListNames(in: controller) == ["Backlog", "Weekend", "Awards"])

        try store.moveUserList(localID: awards, direction: .later)
        #expect(try orderedListNames(in: controller) == ["Backlog", "Weekend", "Awards"])
    }

    @Test
    func reorderAndSortListItemsUpdateSnapshotOrder() throws {
        let controller = PersistenceController(inMemory: true)
        let store = ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)
        let listID = try store.createUserList(name: "Weekend")

        let zodiacID = try store.addToLibrary(movie("Zodiac", localID: "zodiac"))
        let arrivalID = try store.addToLibrary(movie("Arrival", localID: "arrival"))
        let bladeID = try store.addToLibrary(movie("Blade Runner", localID: "blade-runner"))

        try store.setListMembership(itemLocalID: zodiacID, listLocalID: listID, isIncluded: true)
        try store.setListMembership(itemLocalID: arrivalID, listLocalID: listID, isIncluded: true)
        try store.setListMembership(itemLocalID: bladeID, listLocalID: listID, isIncluded: true)

        var snapshot = try userListSnapshot(in: controller, localID: listID)
        #expect(snapshot.items.map(\.title) == ["Zodiac", "Arrival", "Blade Runner"])

        try store.moveListItem(localID: snapshot.listItems[2].listItemLocalID, direction: .earlier)
        snapshot = try userListSnapshot(in: controller, localID: listID)
        #expect(snapshot.items.map(\.title) == ["Zodiac", "Blade Runner", "Arrival"])

        try store.sortListItems(listLocalID: listID, mode: .titleAscending)
        snapshot = try userListSnapshot(in: controller, localID: listID)
        #expect(snapshot.items.map(\.title) == ["Arrival", "Blade Runner", "Zodiac"])

        try store.sortListItems(listLocalID: listID, mode: .titleDescending)
        snapshot = try userListSnapshot(in: controller, localID: listID)
        #expect(snapshot.items.map(\.title) == ["Zodiac", "Blade Runner", "Arrival"])
    }

    @Test
    func seriesGuideListSortModesUseEpisodeProgressAndArticleInsensitiveTitles() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let store = ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)
        let listID = try store.createUserList(name: "Watch Soon")
        let showsJSON = """
        [
          {
            "tmdb_id": 1001,
            "tvdb_id": 2001,
            "title": "The Archive",
            "last_watched_ms": 1700100000000,
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 3001, "episode": 1, "title": "Door", "first_aired": 1577836800000, "watched": true, "plays": 1 },
                  { "tmdb_id": 3002, "episode": 2, "title": "Shelf", "first_aired": 1672531200000, "watched": false, "plays": 0 }
                ]
              }
            ]
          },
          {
            "tmdb_id": 1002,
            "tvdb_id": 2002,
            "title": "A Beacon",
            "last_watched_ms": 1700200000000,
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 3011, "episode": 1, "title": "Signal", "first_aired": 1640995200000, "watched": true, "plays": 1 },
                  { "tmdb_id": 3012, "episode": 2, "title": "Flare", "first_aired": 1704067200000, "watched": false, "plays": 0 },
                  { "tmdb_id": 3013, "episode": 3, "title": "Return", "first_aired": 1735689600000, "watched": false, "plays": 0 }
                ]
              }
            ]
          },
          {
            "tmdb_id": 1003,
            "tvdb_id": 2003,
            "title": "Apollo",
            "last_watched_ms": 1700000000000,
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 3021, "episode": 1, "title": "Launch", "first_aired": 1546300800000, "watched": true, "plays": 1 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(showsJSON.utf8))
        try store.setListMembership(itemLocalID: "seriesguide:show:tvdb:2001", listLocalID: listID, isIncluded: true)
        try store.setListMembership(itemLocalID: "seriesguide:show:tvdb:2002", listLocalID: listID, isIncluded: true)
        try store.setListMembership(itemLocalID: "seriesguide:show:tvdb:2003", listLocalID: listID, isIncluded: true)

        try store.sortListItems(listLocalID: listID, mode: .titleAscendingIgnoringArticles)
        #expect(try userListSnapshot(in: controller, localID: listID).items.map(\.title) == ["Apollo", "The Archive", "A Beacon"])

        try store.sortListItems(listLocalID: listID, mode: .latestEpisode)
        #expect(try userListSnapshot(in: controller, localID: listID).items.map(\.title) == ["A Beacon", "The Archive", "Apollo"])

        try store.sortListItems(listLocalID: listID, mode: .oldestEpisode)
        #expect(try userListSnapshot(in: controller, localID: listID).items.map(\.title) == ["Apollo", "The Archive", "A Beacon"])

        try store.sortListItems(listLocalID: listID, mode: .lastWatched)
        #expect(try userListSnapshot(in: controller, localID: listID).items.map(\.title) == ["A Beacon", "The Archive", "Apollo"])

        try store.sortListItems(listLocalID: listID, mode: .leastRemainingEpisodes)
        #expect(try userListSnapshot(in: controller, localID: listID).items.map(\.title) == ["Apollo", "The Archive", "A Beacon"])
    }

    @Test
    func removeListItemKeepsLibraryItem() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let showJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": []
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

        try ContentLibraryStore(context: controller.container.viewContext).removeListItem(localID: "seriesguide:listitem:68421-firstlist")

        #expect(try entityCount(in: controller, entityName: "UserListItem") == 0)
        #expect(try entityCount(in: controller, entityName: "TrackedItem") == 1)
        _ = try fetchObject(in: controller, entityName: "TrackedItem", localID: "seriesguide:show:tvdb:332331")
    }

    @Test
    func providerIDMatchingAvoidsDuplicatesWhenAddingImportedItemFromTMDB() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let showJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": []
          }
        ]
        """
        _ = try service.importSeriesGuideShows(data: Data(showJSON.utf8))

        let tmdbResult = MediaSummary(
            contentIDs: ContentIDs(localID: "tmdb-result-68421", tmdbID: 68421),
            kind: .show,
            title: "Altered Carbon",
            attribution: .tmdb
        )
        let localID = try ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)
            .addToLibrary(tmdbResult)

        #expect(localID == "seriesguide:show:tvdb:332331")
        #expect(try entityCount(in: controller, entityName: "TrackedItem") == 1)
        let item = try fetchObject(in: controller, entityName: "TrackedItem", localID: localID)
        #expect((item.value(forKey: "tmdbID") as? NSNumber)?.intValue == 68421)
        #expect((item.value(forKey: "tvdbID") as? NSNumber)?.intValue == 332331)
    }

    @Test
    func manageListMembershipAddsAndRemovesLibraryItems() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let store = ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)
        let showJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": []
          }
        ]
        """
        _ = try service.importSeriesGuideShows(data: Data(showJSON.utf8))
        let listID = try store.createUserList(name: "Weekend")

        try store.setListMembership(itemLocalID: "seriesguide:show:tvdb:332331", listLocalID: listID, isIncluded: true)

        var snapshots = UserListSnapshotBuilder(context: controller.container.viewContext)
            .snapshots(from: [try fetchObject(in: controller, entityName: "UserList", localID: listID)])
        #expect(snapshots.first?.items.map(\.title) == ["Altered Carbon"])

        try store.setListMembership(itemLocalID: "seriesguide:show:tvdb:332331", listLocalID: listID, isIncluded: false)

        snapshots = UserListSnapshotBuilder(context: controller.container.viewContext)
            .snapshots(from: [try fetchObject(in: controller, entityName: "UserList", localID: listID)])
        #expect(snapshots.first?.itemCount == 0)
    }

    @Test
    func removeFromLibraryDeletesShowEpisodesAndListMemberships() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let store = ContentLibraryStore(context: controller.container.viewContext, now: fixedDate)
        let showJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "watched": true, "plays": 1 }
                ]
              }
            ]
          }
        ]
        """
        _ = try service.importSeriesGuideShows(data: Data(showJSON.utf8))
        let listID = try store.createUserList(name: "Weekend")
        try store.setListMembership(itemLocalID: "seriesguide:show:tvdb:332331", listLocalID: listID, isIncluded: true)

        try store.removeFromLibrary(localID: "seriesguide:show:tvdb:332331", kind: .show)

        #expect(try entityCount(in: controller, entityName: "TrackedItem") == 0)
        #expect(try entityCount(in: controller, entityName: "EpisodeState") == 0)
        #expect(try entityCount(in: controller, entityName: "UserListItem") == 0)
    }
}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

private func movie(_ title: String, localID: String) -> MediaSummary {
    MediaSummary(
        contentIDs: ContentIDs(localID: localID),
        kind: .movie,
        title: title,
        attribution: .tmdb
    )
}

@MainActor
private func fetchObject(in controller: PersistenceController, entityName: String, localID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.predicate = NSPredicate(format: "localID == %@", localID)

    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func orderedListNames(in controller: PersistenceController) throws -> [String] {
    let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
    request.sortDescriptors = [
        NSSortDescriptor(key: "sortOrder", ascending: true),
        NSSortDescriptor(key: "name", ascending: true)
    ]

    return try controller.container.viewContext.fetch(request)
        .map { $0.value(forKey: "name") as? String ?? "" }
}

@MainActor
private func userListSnapshot(in controller: PersistenceController, localID: String) throws -> UserListSnapshot {
    let list = try fetchObject(in: controller, entityName: "UserList", localID: localID)
    return try #require(
        UserListSnapshotBuilder(context: controller.container.viewContext)
            .snapshots(from: [list])
            .first
    )
}

@MainActor
private func entityCount(in controller: PersistenceController, entityName: String) throws -> Int {
    try controller.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
}
