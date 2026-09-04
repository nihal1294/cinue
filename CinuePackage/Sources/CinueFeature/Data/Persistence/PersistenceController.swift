import CoreData
import Foundation

enum PersistenceMode: Equatable, Sendable {
    case localOnly
    case cloudKit(containerIdentifier: String)
    case inMemory

    var isCloudKitEnabled: Bool {
        switch self {
        case .cloudKit:
            true
        case .localOnly, .inMemory:
            false
        }
    }
}

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController(mode: .localOnly)

    let container: NSPersistentContainer
    let mode: PersistenceMode

    convenience init(inMemory: Bool) {
        self.init(mode: inMemory ? .inMemory : .localOnly)
    }

    init(mode: PersistenceMode) {
        self.mode = mode

        switch mode {
        case .cloudKit:
            container = NSPersistentCloudKitContainer(
                name: "Cinue",
                managedObjectModel: Self.makeManagedObjectModel()
            )
        case .localOnly, .inMemory:
            container = NSPersistentContainer(
                name: "Cinue",
                managedObjectModel: Self.makeManagedObjectModel()
            )
        }

        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()

        switch mode {
        case .cloudKit(let containerIdentifier):
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: containerIdentifier
            )
        case .localOnly:
            description.cloudKitContainerOptions = nil
        case .inMemory:
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(UUID().uuidString)")
            description.cloudKitContainerOptions = nil
        }

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            fatalError("Failed to load persistent stores: \(loadError)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        if let modelURL = Bundle.module.url(forResource: "Cinue", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: modelURL) {
            return model
        }

        if let modelURL = Bundle.module.url(forResource: "Cinue", withExtension: "mom"),
           let model = NSManagedObjectModel(contentsOf: modelURL) {
            return model
        }

        if let model = NSManagedObjectModel.mergedModel(from: [Bundle.module]) {
            return model
        }

        fatalError("Failed to load Cinue Core Data model")
    }
}
