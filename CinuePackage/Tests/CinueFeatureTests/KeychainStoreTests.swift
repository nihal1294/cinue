import Foundation
import Testing
@testable import CinueFeature

struct KeychainStoreTests {
    @Test
    func saveReadDeleteRoundTrip() throws {
        let account = "test.tmdb.\(UUID().uuidString)"
        let store = KeychainStore(service: "com.nihal.Cinue.tests", backend: InMemoryKeychainBackend())

        try store.save("secret-value", account: account)
        #expect(try store.read(account: account) == "secret-value")

        try store.delete(account: account)
        #expect(try store.read(account: account) == nil)
    }

    @Test
    func saveUpdatesExistingValue() throws {
        let account = "test.tvdb.\(UUID().uuidString)"
        let store = KeychainStore(service: "com.nihal.Cinue.tests", backend: InMemoryKeychainBackend())

        try store.save("first-value", account: account)
        try store.save("updated-value", account: account)

        #expect(try store.read(account: account) == "updated-value")
    }
}

private final class InMemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ value: String, service: String, account: String) throws {
        lock.withLock {
            values[key(service: service, account: account)] = value
        }
    }

    func read(service: String, account: String) throws -> String? {
        lock.withLock {
            values[key(service: service, account: account)]
        }
    }

    func delete(service: String, account: String) throws {
        lock.withLock {
            _ = values.removeValue(forKey: key(service: service, account: account))
        }
    }

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}
