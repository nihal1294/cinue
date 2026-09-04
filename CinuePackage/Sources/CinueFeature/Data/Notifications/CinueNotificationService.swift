import CoreData
import Foundation
import UserNotifications

enum CinueNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

enum CinueNotificationRefreshStatus: Equatable {
    case disabled
    case permissionRequired
    case denied
    case scheduled
    case failed
}

struct CinueNotificationRefreshSummary: Equatable {
    var status: CinueNotificationRefreshStatus
    var scheduledCount: Int

    var message: String {
        switch status {
        case .disabled:
            return "Episode reminders are off."
        case .permissionRequired:
            return "Notification permission is needed before reminders can be scheduled."
        case .denied:
            return "Notifications are disabled in system settings."
        case .scheduled:
            return scheduledCount == 1 ? "1 episode reminder scheduled." : "\(scheduledCount) episode reminders scheduled."
        case .failed:
            return "Could not update episode reminders."
        }
    }
}

struct CinueNotificationRequest: Equatable, Identifiable {
    var id: String
    var title: String
    var body: String
    var date: Date
    var userInfo: [String: String]
}

@MainActor
protocol CinueNotificationScheduling {
    func currentAuthorizationStatus() async -> CinueNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replaceEpisodeNotifications(with requests: [CinueNotificationRequest]) async throws
}

@MainActor
struct UserNotificationScheduler: CinueNotificationScheduling {
    private let center: UNUserNotificationCenter
    private let identifierPrefix = "cinue.episode."

    init() {
        center = .current()
    }

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func currentAuthorizationStatus() async -> CinueNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func replaceEpisodeNotifications(with requests: [CinueNotificationRequest]) async throws {
        let pending = await center.pendingNotificationRequests()
        let episodeRequestIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: episodeRequestIDs)

        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.userInfo = request.userInfo

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: request.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let notificationRequest = UNNotificationRequest(
                identifier: request.id,
                content: content,
                trigger: trigger
            )
            try await center.add(notificationRequest)
        }
    }
}

@MainActor
struct NoOpNotificationScheduler: CinueNotificationScheduling {
    func currentAuthorizationStatus() async -> CinueNotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func replaceEpisodeNotifications(with requests: [CinueNotificationRequest]) async throws {}
}

@MainActor
final class CinueNotificationService {
    private let persistence: PersistenceController
    private let scheduler: CinueNotificationScheduling
    private let now: () -> Date
    private let maxPendingRequests: Int

    init(
        persistence: PersistenceController,
        scheduler: CinueNotificationScheduling = NoOpNotificationScheduler(),
        now: @escaping () -> Date = Date.init,
        maxPendingRequests: Int = 64
    ) {
        self.persistence = persistence
        self.scheduler = scheduler
        self.now = now
        self.maxPendingRequests = maxPendingRequests
    }

    func refreshUpcomingEpisodeNotifications(
        isEnabled: Bool = CinuePreferences.episodeNotificationsEnabled,
        leadTime: TimeInterval = CinuePreferences.episodeNotificationLeadTime,
        requestAuthorizationIfNeeded: Bool = true
    ) async -> CinueNotificationRefreshSummary {
        guard isEnabled else {
            do {
                try await scheduler.replaceEpisodeNotifications(with: [])
                return CinueNotificationRefreshSummary(status: .disabled, scheduledCount: 0)
            } catch {
                return CinueNotificationRefreshSummary(status: .failed, scheduledCount: 0)
            }
        }

        do {
            let authorizationStatus = await scheduler.currentAuthorizationStatus()
            switch authorizationStatus {
            case .notDetermined where requestAuthorizationIfNeeded:
                let granted = try await scheduler.requestAuthorization()
                guard granted else {
                    return CinueNotificationRefreshSummary(status: .denied, scheduledCount: 0)
                }
            case .notDetermined:
                return CinueNotificationRefreshSummary(status: .permissionRequired, scheduledCount: 0)
            case .denied:
                return CinueNotificationRefreshSummary(status: .denied, scheduledCount: 0)
            case .authorized, .provisional, .ephemeral:
                break
            }

            let requests = upcomingEpisodeRequests(leadTime: leadTime)
            try await scheduler.replaceEpisodeNotifications(with: requests)
            return CinueNotificationRefreshSummary(status: .scheduled, scheduledCount: requests.count)
        } catch {
            return CinueNotificationRefreshSummary(status: .failed, scheduledCount: 0)
        }
    }

    private func upcomingEpisodeRequests(leadTime: TimeInterval) -> [CinueNotificationRequest] {
        let currentDate = now()
        return visibleShows()
            .compactMap { show -> MediaDetailSnapshot? in
                let localID = show.value(forKey: "localID") as? String ?? ""
                guard localID.isEmpty == false else {
                    return nil
                }

                return MediaDetailSnapshotBuilder(context: persistence.container.viewContext)
                    .snapshot(localID: localID, kind: .show)
            }
            .flatMap { snapshot in
                snapshot.episodes.compactMap { episode in
                    notificationRequest(
                        for: episode,
                        showTitle: snapshot.title,
                        currentDate: currentDate,
                        leadTime: leadTime
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }

                return lhs.body.localizedStandardCompare(rhs.body) == .orderedAscending
            }
            .prefix(maxPendingRequests)
            .map { $0 }
    }

    private func notificationRequest(
        for episode: EpisodeDetailSnapshot,
        showTitle: String,
        currentDate: Date,
        leadTime: TimeInterval
    ) -> CinueNotificationRequest? {
        guard episode.isWatched == false,
              episode.isSkipped == false,
              let airDate = episode.airDate,
              airDate > currentDate
        else {
            return nil
        }

        let preferredDate = airDate.addingTimeInterval(-max(leadTime, 0))
        let notificationDate = preferredDate > currentDate ? preferredDate : airDate

        return CinueNotificationRequest(
            id: "cinue.episode.\(episode.localID)",
            title: showTitle,
            body: episode.titleLine,
            date: notificationDate,
            userInfo: [
                "showLocalID": episode.showLocalID,
                "season": "\(episode.seasonNumber)",
                "episode": "\(episode.episodeNumber ?? 0)"
            ]
        )
    }

    private func visibleShows() -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.returnsObjectsAsFaults = false
        request.predicate = NSPredicate(format: "kindRaw == %@ AND isHidden == NO", MediaKind.show.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]
        return (try? persistence.container.viewContext.fetch(request)) ?? []
    }
}
