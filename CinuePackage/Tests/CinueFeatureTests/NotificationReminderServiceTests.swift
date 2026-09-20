import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct NotificationReminderServiceTests {
    @Test
    func schedulesOnlyFutureUnwatchedVisibleEpisodes() async throws {
        let controller = PersistenceController(inMemory: true)
        let scheduler = RecordingNotificationScheduler(status: .authorized)
        let service = CinueNotificationService(
            persistence: controller,
            scheduler: scheduler,
            now: fixedDate,
            maxPendingRequests: 64
        )
        try seedNotificationFixture(in: controller)

        let summary = await service.refreshUpcomingEpisodeNotifications(
            isEnabled: true,
            leadTime: 0,
            requestAuthorizationIfNeeded: false
        )

        #expect(summary.status == .scheduled)
        #expect(summary.scheduledCount == 1)
        #expect(scheduler.replacedRequests.map(\.title) == ["Altered Carbon"])
        #expect(scheduler.replacedRequests.map(\.body) == ["1x03 Fresh Upload"])
        #expect(scheduler.replacedRequests.first?.date == futureEpisodeDate())
        #expect(scheduler.replacedRequests.first?.userInfo["showLocalID"] == "seriesguide:show:tvdb:332331")
    }

    @Test
    func disabledNotificationsClearEpisodeRequests() async throws {
        let controller = PersistenceController(inMemory: true)
        let scheduler = RecordingNotificationScheduler(status: .authorized)
        let service = CinueNotificationService(
            persistence: controller,
            scheduler: scheduler,
            now: fixedDate
        )
        try seedNotificationFixture(in: controller)

        let summary = await service.refreshUpcomingEpisodeNotifications(
            isEnabled: false,
            leadTime: 0,
            requestAuthorizationIfNeeded: false
        )

        #expect(summary.status == .disabled)
        #expect(summary.scheduledCount == 0)
        #expect(scheduler.didReplaceRequests)
        #expect(scheduler.replacedRequests.isEmpty)
    }

    @Test
    func leadTimeSchedulesBeforeAirDateWhenStillFuture() async throws {
        let controller = PersistenceController(inMemory: true)
        let scheduler = RecordingNotificationScheduler(status: .authorized)
        let service = CinueNotificationService(
            persistence: controller,
            scheduler: scheduler,
            now: fixedDate
        )
        try seedNotificationFixture(in: controller)

        _ = await service.refreshUpcomingEpisodeNotifications(
            isEnabled: true,
            leadTime: 60 * 60,
            requestAuthorizationIfNeeded: false
        )

        #expect(scheduler.replacedRequests.first?.date == futureEpisodeDate().addingTimeInterval(-60 * 60))
    }

    @Test
    func permissionCanBeRequestedBeforeScheduling() async throws {
        let controller = PersistenceController(inMemory: true)
        let scheduler = RecordingNotificationScheduler(status: .notDetermined, authorizationResult: true)
        let service = CinueNotificationService(
            persistence: controller,
            scheduler: scheduler,
            now: fixedDate
        )
        try seedNotificationFixture(in: controller)

        let summary = await service.refreshUpcomingEpisodeNotifications(
            isEnabled: true,
            leadTime: 0,
            requestAuthorizationIfNeeded: true
        )

        #expect(summary.status == .scheduled)
        #expect(scheduler.didRequestAuthorization)
        #expect(scheduler.replacedRequests.count == 1)
    }
}

@MainActor
private final class RecordingNotificationScheduler: CinueNotificationScheduling {
    private(set) var authorizationStatus: CinueNotificationAuthorizationStatus
    private(set) var replacedRequests: [CinueNotificationRequest] = []
    private(set) var didReplaceRequests = false
    private(set) var didRequestAuthorization = false
    private let authorizationResult: Bool

    init(
        status: CinueNotificationAuthorizationStatus,
        authorizationResult: Bool = false
    ) {
        authorizationStatus = status
        self.authorizationResult = authorizationResult
    }

    func currentAuthorizationStatus() async -> CinueNotificationAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        didRequestAuthorization = true
        authorizationStatus = authorizationResult ? .authorized : .denied
        return authorizationResult
    }

    func replaceEpisodeNotifications(with requests: [CinueNotificationRequest]) async throws {
        didReplaceRequests = true
        replacedRequests = requests
    }
}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

private func futureEpisodeDate() -> Date {
    fixedDate().addingTimeInterval(60 * 60 * 6)
}

@MainActor
private func seedNotificationFixture(in controller: PersistenceController) throws {
    let service = BackupService(persistence: controller, now: fixedDate)
    let futureMilliseconds = Int64(futureEpisodeDate().timeIntervalSince1970 * 1_000)
    let pastMilliseconds = Int64(fixedDate().addingTimeInterval(-60 * 60 * 24).timeIntervalSince1970 * 1_000)
    let hiddenFutureMilliseconds = Int64(fixedDate().addingTimeInterval(60 * 60 * 12).timeIntervalSince1970 * 1_000)
    let json = """
    [
      {
        "tmdb_id": 68421,
        "tvdb_id": 332331,
        "title": "Altered Carbon",
        "hidden": false,
        "seasons": [
          {
            "season": 1,
            "episodes": [
              { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "first_aired": \(pastMilliseconds), "watched": false, "plays": 0 },
              { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "first_aired": \(futureMilliseconds), "watched": true, "plays": 1 },
              { "tmdb_id": 1401625, "episode": 3, "title": "Fresh Upload", "first_aired": \(futureMilliseconds), "watched": false, "plays": 0 },
              { "tmdb_id": 1401626, "episode": 4, "title": "Skipped Future", "first_aired": \(futureMilliseconds), "watched": false, "plays": 0, "skipped": true }
            ]
          }
        ]
      },
      {
        "tmdb_id": 70001,
        "tvdb_id": 80001,
        "title": "Hidden Show",
        "hidden": true,
        "seasons": [
          {
            "season": 1,
            "episodes": [
              { "tmdb_id": 90001, "episode": 1, "title": "Hidden Future", "first_aired": \(hiddenFutureMilliseconds), "watched": false, "plays": 0 }
            ]
          }
        ]
      }
    ]
    """

    _ = try service.importSeriesGuideShows(data: Data(json.utf8))
}
