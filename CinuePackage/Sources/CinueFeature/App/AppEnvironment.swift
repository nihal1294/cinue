import Foundation
import Observation

@MainActor
@Observable
public final class AppEnvironment {
    var router: AppRouter
    let persistence: PersistenceController
    let keychain: KeychainStore
    let tmdbClient: TMDBClient
    let artworkPipeline: any ArtworkImageLoading
    let backupService: BackupService
    let metadataRefreshService: MetadataRefreshService
    let notificationService: CinueNotificationService
    private var isRefreshingMetadata = false

    init(
        router: AppRouter,
        persistence: PersistenceController,
        keychain: KeychainStore,
        tmdbClient: TMDBClient,
        artworkPipeline: any ArtworkImageLoading,
        backupService: BackupService,
        metadataRefreshService: MetadataRefreshService,
        notificationService: CinueNotificationService
    ) {
        self.router = router
        self.persistence = persistence
        self.keychain = keychain
        self.tmdbClient = tmdbClient
        self.artworkPipeline = artworkPipeline
        self.backupService = backupService
        self.metadataRefreshService = metadataRefreshService
        self.notificationService = notificationService
    }

    public static func live() -> AppEnvironment {
        if ProcessInfo.processInfo.arguments.contains(Self.uiTestSeedArgument) {
            return uiTestSeeded()
        }

        let keychain = KeychainStore()
        let persistence = PersistenceController.shared
        let tmdb = TMDBClient(apiKey: { try keychain.read(account: "tmdb.apiKey") })

        return AppEnvironment(
            router: AppRouter(),
            persistence: persistence,
            keychain: keychain,
            tmdbClient: tmdb,
            artworkPipeline: ArtworkImagePipeline.live(),
            backupService: BackupService(persistence: persistence),
            metadataRefreshService: MetadataRefreshService(persistence: persistence, tmdbClient: tmdb),
            notificationService: CinueNotificationService(
                persistence: persistence,
                scheduler: UserNotificationScheduler()
            )
        )
    }

    static func preview() -> AppEnvironment {
        let persistence = PersistenceController(inMemory: true)
        let tmdb = TMDBClient(apiKey: { nil })

        return AppEnvironment(
            router: AppRouter(),
            persistence: persistence,
            keychain: KeychainStore(),
            tmdbClient: tmdb,
            artworkPipeline: DisabledArtworkImageLoader(),
            backupService: BackupService(persistence: persistence),
            metadataRefreshService: MetadataRefreshService(persistence: persistence, tmdbClient: tmdb),
            notificationService: CinueNotificationService(persistence: persistence)
        )
    }

    public func prepareForAppOpen() async {
        await refreshMetadataOnAppOpen()
        await refreshNotificationsOnAppOpen()
    }

    public func refreshMetadataOnAppOpen() async {
        guard isRefreshingMetadata == false else {
            return
        }

        isRefreshingMetadata = true
        _ = await metadataRefreshService.refreshStaleMetadata()
        isRefreshingMetadata = false
    }

    public func refreshNotificationsOnAppOpen() async {
        _ = await notificationService.refreshUpcomingEpisodeNotifications(requestAuthorizationIfNeeded: false)
    }

    private static let uiTestSeedArgument = "--cinue-ui-test-seed"

    private static func uiTestSeeded() -> AppEnvironment {
        let keychain = KeychainStore(service: "com.nihal.Cinue.providers.uiTests")
        let persistence = PersistenceController(inMemory: true)
        let backupService = BackupService(persistence: persistence, now: uiTestNow)

        do {
            try keychain.delete(account: "tmdb.apiKey")
            try seedUITestData(using: backupService)
        } catch {
            fatalError("Failed to seed Cinue UI test data: \(error)")
        }

        let tmdb = TMDBClient(apiKey: { "ui-test-key" }, transport: uiTestTMDBTransport)

        return AppEnvironment(
            router: AppRouter(),
            persistence: persistence,
            keychain: keychain,
            tmdbClient: tmdb,
            artworkPipeline: DisabledArtworkImageLoader(),
            backupService: backupService,
            metadataRefreshService: MetadataRefreshService(persistence: persistence, tmdbClient: tmdb),
            notificationService: CinueNotificationService(persistence: persistence)
        )
    }

    private static func seedUITestData(using backupService: BackupService) throws {
        let now = uiTestNow()
        let releasedMilliseconds = milliseconds(from: Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now)
        let movieReleaseMilliseconds = milliseconds(from: Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now)
        let watchedMilliseconds = milliseconds(from: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)

        let showsJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "imdb_id": "tt2261227",
            "title": "Altered Carbon",
            "overview": "A stack returns.",
            "poster": "/66rKwpSexUZ3yTv5lBS1bjU4Ykk.jpg",
            "favorite": true,
            "hidden": false,
            "last_watched_ms": \(watchedMilliseconds),
            "rating_user": 9,
            "user_note": "Stack watch",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  {
                    "tmdb_id": 1401623,
                    "episode": 1,
                    "title": "Out of the Past",
                    "overview": "Takeshi Kovacs wakes in a new body.",
                    "first_aired": \(watchedMilliseconds),
                    "watched": true,
                    "plays": 1
                  },
                  {
                    "tmdb_id": 1401624,
                    "episode": 2,
                    "title": "Fallen Angel",
                    "overview": "A case starts to unravel.",
                    "first_aired": \(releasedMilliseconds),
                    "watched": false,
                    "plays": 0
                  },
                  {
                    "tmdb_id": 1401625,
                    "episode": 3,
                    "title": "Fresh Upload",
                    "overview": "A new case arrives.",
                    "first_aired": \(releasedMilliseconds),
                    "watched": false,
                    "plays": 0
                  }
                ]
              }
            ]
          }
        ]
        """

        let moviesJSON = """
        [
          {
            "tmdb_id": 19913,
            "imdb_id": "tt1022603",
            "title": "(500) Days of Summer",
            "overview": "A romance is remembered.",
            "watched": false,
            "plays": 0,
            "in_watchlist": true,
            "poster": "/qXAuQ9hF30sQRsXf40OfRVl0MJZ.jpg",
            "released_utc_ms": \(movieReleaseMilliseconds),
            "runtime_min": 95
          }
        ]
        """

        let listsJSON = """
        [
          {
            "items": [
              {
                "externalId": "68421",
                "list_item_id": "68421-weekend",
                "tvdb_id": 0,
                "type": "tmdb-show"
              }
            ],
            "list_id": "Weekend",
            "name": "Weekend",
            "order": 0
          }
        ]
        """

        _ = try backupService.importSeriesGuideShows(data: Data(showsJSON.utf8))
        _ = try backupService.importSeriesGuideMovies(data: Data(moviesJSON.utf8))
        _ = try backupService.importSeriesGuideLists(data: Data(listsJSON.utf8))
    }

    nonisolated private static func uiTestTMDBTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let resultsJSON: String
        if path == "/3/tv/68421" {
            resultsJSON = """
            {
              "id": 68421,
              "name": "Altered Carbon",
              "overview": "A stack returns.",
              "first_air_date": "2018-02-02",
              "poster_path": "/66rKwpSexUZ3yTv5lBS1bjU4Ykk.jpg",
              "backdrop_path": "/A6I3M4MIA2Pi2gS6vGdg2eVlVXT.jpg",
              "status": "Returning Series",
              "next_episode_to_air": {
                "id": 1401625,
                "name": "Fresh Upload",
                "overview": "A new case arrives.",
                "air_date": "2026-05-01",
                "season_number": 1,
                "episode_number": 3,
                "still_path": "/xzFFWUm3Lb6f8MqpGSGae5kmdPc.jpg"
              }
            }
            """
        } else if path == "/3/movie/19913" {
            resultsJSON = """
            {
              "id": 19913,
              "title": "(500) Days of Summer",
              "overview": "A romance is remembered.",
              "release_date": "2009-07-17",
              "poster_path": "/qXAuQ9hF30sQRsXf40OfRVl0MJZ.jpg",
              "backdrop_path": "/1M2i4Mxd03elGOTmEkIvqrHfmyS.jpg"
            }
            """
        } else {
            resultsJSON = """
        {
          "page": 1,
          "results": [
            {
              "id": 95396,
              "media_type": "tv",
              "name": "Severance",
              "original_name": "Severance",
              "overview": "Employees split their memories between work and home.",
              "first_air_date": "2022-02-18",
              "poster_path": "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg",
              "backdrop_path": "/ixgFmf1X59PUZam2qbAfskx2gQr.jpg"
            },
            {
              "id": 550,
              "media_type": "movie",
              "title": "Fight Club",
              "original_title": "Fight Club",
              "overview": "An office worker meets a soap maker.",
              "release_date": "1999-10-15",
              "poster_path": "/jSziioSwPVrOy9Yow3XhWIBDjq1.jpg",
              "backdrop_path": "/c6OLXfKAk5BKeR6broC8pYiCquX.jpg"
            }
          ]
        }
        """
        }
        let data = Data(resultsJSON.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.themoviedb.org")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) ?? URLResponse()

        return (data, response)
    }

    nonisolated private static func uiTestNow() -> Date {
        Date(timeIntervalSince1970: 1_777_000_000)
    }

    nonisolated private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
