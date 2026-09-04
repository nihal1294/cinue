import CoreData
import Testing
@testable import CinueFeature

struct PersistenceControllerTests {
    @Test
    func sharedPersistenceDefaultsToLocalOnly() {
        let controller = PersistenceController.shared

        #expect(controller.mode == .localOnly)
        #expect(controller.mode.isCloudKitEnabled == false)
    }

    @Test
    func inMemoryPersistenceLoadsExpectedEntities() throws {
        let controller = PersistenceController(inMemory: true)

        #expect(controller.mode == .inMemory)

        let entityNames = Set(controller.container.managedObjectModel.entities.compactMap(\.name))
        #expect(entityNames.isSuperset(of: [
            "TrackedItem",
            "EpisodeState",
            "UserList",
            "UserListItem",
            "MetadataRecord",
            "ProviderSetting"
        ]))

        let store = try #require(controller.container.persistentStoreCoordinator.persistentStores.first)
        #expect(store.type == NSInMemoryStoreType)
    }

    @Test
    func inMemoryStoreCanSaveTrackedItem() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let item = NSEntityDescription.insertNewObject(forEntityName: "TrackedItem", into: context)

        item.setValue("local-1", forKey: "localID")
        item.setValue("show", forKey: "kindRaw")
        item.setValue("Example Show", forKey: "title")
        item.setValue("unwatched", forKey: "statusRaw")
        item.setValue(0, forKey: "watchCount")
        item.setValue(false, forKey: "isCollected")
        item.setValue(false, forKey: "isFavorite")
        item.setValue(false, forKey: "isHidden")
        item.setValue(Date(), forKey: "createdAt")
        item.setValue(Date(), forKey: "updatedAt")

        try context.save()

        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.predicate = NSPredicate(format: "localID == %@", "local-1")

        #expect(try context.count(for: request) == 1)
    }

    @MainActor
    @Test
    func previewEnvironmentUsesInMemoryPersistence() throws {
        let environment = AppEnvironment.preview()
        let store = try #require(environment.persistence.container.persistentStoreCoordinator.persistentStores.first)

        #expect(store.type == NSInMemoryStoreType)
    }
}
