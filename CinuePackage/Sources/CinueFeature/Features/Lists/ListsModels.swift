import CoreData
import Foundation

struct UserListSnapshot: Equatable, Identifiable {
    let id: String
    let localID: String
    let name: String
    let itemCount: Int
    let resolvedItemCount: Int
    let listItems: [UserListItemSnapshot]

    var items: [LibraryItemSnapshot] {
        listItems.map(\.item)
    }

    var unresolvedItemCount: Int {
        max(itemCount - resolvedItemCount, 0)
    }

    var subtitle: String {
        if itemCount == 0 {
            return "No items"
        }

        if unresolvedItemCount > 0 {
            return "\(resolvedItemCount) of \(itemCount) items available"
        }

        return itemCount == 1 ? "1 item" : "\(itemCount) items"
    }
}

struct UserListItemSnapshot: Equatable, Identifiable {
    let id: String
    let listItemLocalID: String
    let item: LibraryItemSnapshot
}

@MainActor
struct UserListSnapshotBuilder {
    let context: NSManagedObjectContext

    func snapshots(from userLists: [NSManagedObject]) -> [UserListSnapshot] {
        let listLocalIDs = userLists
            .map { stringValue($0, forKey: "localID") }
            .filter { $0.isEmpty == false }

        guard listLocalIDs.isEmpty == false else {
            return []
        }

        let listItems = fetchListItems(for: listLocalIDs)
        let trackedItems = fetchTrackedItems()
        let resolver = ListItemResolver(trackedItems: trackedItems)
        let snapshotsByLocalID = LibraryItemSnapshotBuilder(context: context)
            .snapshots(from: trackedItems)
            .reduce(into: [:]) { result, snapshot in
                result[snapshot.localID] = snapshot
            }

        let itemSnapshotsByListID = listItems.reduce(into: [String: [UserListItemSnapshot]]()) { result, listItem in
            guard
                let trackedItem = resolver.trackedItem(for: listItem),
                let snapshot = snapshotsByLocalID[stringValue(trackedItem, forKey: "localID")]
            else {
                return
            }

            let listItemSnapshot = UserListItemSnapshot(
                id: stringValue(listItem, forKey: "localID"),
                listItemLocalID: stringValue(listItem, forKey: "localID"),
                item: snapshot
            )
            result[stringValue(listItem, forKey: "listLocalID"), default: []].append(listItemSnapshot)
        }

        let itemCountsByListID = Dictionary(grouping: listItems) { listItem in
            stringValue(listItem, forKey: "listLocalID")
        }
        .mapValues(\.count)

        return userLists.map { list in
            let localID = stringValue(list, forKey: "localID")
            let listItems = itemSnapshotsByListID[localID] ?? []

            return UserListSnapshot(
                id: localID,
                localID: localID,
                name: stringValue(list, forKey: "name", fallback: "Untitled List"),
                itemCount: itemCountsByListID[localID] ?? 0,
                resolvedItemCount: listItems.count,
                listItems: listItems
            )
        }
    }

    private func fetchListItems(for listLocalIDs: [String]) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "listLocalID IN %@", listLocalIDs)
        request.sortDescriptors = [
            NSSortDescriptor(key: "listLocalID", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private func fetchTrackedItems() -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.returnsObjectsAsFaults = false
        request.sortDescriptors = [
            NSSortDescriptor(key: "kindRaw", ascending: false),
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }

    private func stringValue(_ object: NSManagedObject?, forKey key: String, fallback: String = "") -> String {
        object?.value(forKey: key) as? String ?? fallback
    }
}

private struct ListItemResolver {
    private let byLocalID: [String: NSManagedObject]
    private let byTVDBID: [String: NSManagedObject]
    private let byTMDBID: [String: NSManagedObject]
    private let byExternalID: [String: NSManagedObject]

    init(trackedItems: [NSManagedObject]) {
        var localIDMap = [String: NSManagedObject]()
        var tvdbIDMap = [String: NSManagedObject]()
        var tmdbIDMap = [String: NSManagedObject]()
        var externalIDMap = [String: NSManagedObject]()

        for item in trackedItems {
            let kindRaw = item.stringValue(forKey: "kindRaw")
            let localID = item.stringValue(forKey: "localID")
            if localID.isEmpty == false {
                localIDMap[localID] = item
            }

            if let tvdbID = item.optionalIntValue(forKey: "tvdbID") {
                tvdbIDMap[Self.key(kindRaw: kindRaw, provider: "tvdb", id: tvdbID)] = item
                externalIDMap[Self.key(kindRaw: kindRaw, provider: "external", id: tvdbID)] = item
            }

            if let tmdbID = item.optionalIntValue(forKey: "tmdbID") {
                tmdbIDMap[Self.key(kindRaw: kindRaw, provider: "tmdb", id: tmdbID)] = item
                externalIDMap[Self.key(kindRaw: kindRaw, provider: "external", id: tmdbID)] = item
            }
        }

        byLocalID = localIDMap
        byTVDBID = tvdbIDMap
        byTMDBID = tmdbIDMap
        byExternalID = externalIDMap
    }

    func trackedItem(for listItem: NSManagedObject) -> NSManagedObject? {
        let kindRaw = listItem.stringValue(forKey: "kindRaw")

        if let itemLocalID = listItem.optionalStringValue(forKey: "itemLocalID"),
           let item = byLocalID[itemLocalID] {
            return item
        }

        if let tvdbID = listItem.optionalIntValue(forKey: "tvdbID"),
           let item = byTVDBID[Self.key(kindRaw: kindRaw, provider: "tvdb", id: tvdbID)] {
            return item
        }

        if let tmdbID = listItem.optionalIntValue(forKey: "tmdbID"),
           let item = byTMDBID[Self.key(kindRaw: kindRaw, provider: "tmdb", id: tmdbID)] {
            return item
        }

        if let externalID = listItem.optionalStringValue(forKey: "externalID"),
           let externalIntID = Int(externalID),
           let item = byExternalID[Self.key(kindRaw: kindRaw, provider: "external", id: externalIntID)] {
            return item
        }

        return nil
    }

    private static func key(kindRaw: String, provider: String, id: Int) -> String {
        "\(kindRaw):\(provider):\(id)"
    }
}

private extension NSManagedObject {
    func stringValue(forKey key: String) -> String {
        value(forKey: key) as? String ?? ""
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
}
