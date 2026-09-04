import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct MediaDetailSnapshotTests {
    @Test
    func nextEpisodeSelectorsOnlyReturnReleasedEpisodesAtTheSnapshotTime() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        [
          {
            "tmdb_id": 1,
            "tvdb_id": 2,
            "title": "Release Schedule",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1, "episode": 1, "title": "Watched", "first_aired": 1600000000000, "watched": true, "plays": 1 },
                  { "tmdb_id": 2, "episode": 2, "title": "Future First", "first_aired": 1800000000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 3, "episode": 3, "title": "Undated", "watched": false, "plays": 0 },
                  { "tmdb_id": 4, "episode": 4, "title": "Released", "first_aired": 1690000000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 5, "episode": 5, "title": "Released Exactly Now", "first_aired": 1700000000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 6, "episode": 6, "title": "Future Last", "first_aired": 1800000000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let builder = MediaDetailSnapshotBuilder(context: controller.container.viewContext)
        let snapshot = try #require(
            builder.snapshot(localID: "seriesguide:show:tvdb:2", kind: .show)
        )
        let watchedEpisode = try #require(snapshot.episodes.first { $0.episodeNumber == 1 })
        let releasedEpisode = try #require(snapshot.episodes.first { $0.episodeNumber == 4 })
        let equalityEpisode = try #require(snapshot.episodes.first { $0.episodeNumber == 5 })

        #expect(snapshot.nextEpisode(asOf: asOf)?.episodeNumber == 4)
        #expect(snapshot.nextEpisode(after: watchedEpisode, asOf: asOf)?.episodeNumber == 4)
        #expect(snapshot.nextEpisode(after: releasedEpisode, asOf: asOf)?.episodeNumber == 5)
        #expect(snapshot.nextEpisode(after: equalityEpisode, asOf: asOf) == nil)
        #expect(
            builder.nextEpisode(
                afterShowLocalID: "seriesguide:show:tvdb:2",
                season: 1,
                episode: 1,
                asOf: asOf
            )?.episodeNumber == 4
        )
    }

    @Test
    func showDetailSnapshotUsesMetadataAndEpisodesWithoutProviderIDs() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "overview": "A stack returns.",
            "poster": "/poster.jpg",
            "rating_user": 9,
            "user_note": "Private note",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "first_aired": 1600000000000, "watched": true, "plays": 1 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "first_aired": 1600000000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let snapshot = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .snapshot(localID: "seriesguide:show:tvdb:332331", kind: .show)
        )

        #expect(snapshot.title == "Altered Carbon")
        #expect(snapshot.overview == "A stack returns.")
        #expect(snapshot.notes == "Private note")
        #expect(snapshot.userRating == 9)
        #expect(snapshot.episodes.count == 2)
        #expect(snapshot.nextEpisode?.titleLine == "1x02 Fallen Angel")
        #expect(snapshot.item.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(snapshot.artworkBackgroundURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(snapshot.nextEpisode?.accessibilityLabel.contains("332331") == false)
        #expect(snapshot.nextEpisode?.accessibilityLabel.contains("68421") == false)
    }

    @Test
    func detailSnapshotExtractsTMDBCastTrailersAndSimilarItemsFromRawMetadata() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": []
          }
        ]
        """
        let tmdbRawJSON = """
        {
          "id": 68421,
          "name": "Altered Carbon",
          "credits": {
            "cast": [
              { "id": 1, "name": "Joel Kinnaman", "character": "Takeshi Kovacs", "profile_path": "/joel.jpg", "order": 0 },
              { "id": 2, "name": "Martha Higareda", "character": "Kristin Ortega", "profile_path": "/martha.jpg", "order": 1 }
            ],
            "crew": [
              { "id": 3, "name": "Laeta Kalogridis", "job": "Creator", "department": "Writing" }
            ]
          },
          "videos": {
            "results": [
              { "id": "trailer-1", "name": "Official Trailer", "site": "YouTube", "key": "abc123", "type": "Trailer", "official": true },
              { "id": "clip-1", "name": "Clip", "site": "YouTube", "key": "clip123", "type": "Clip", "official": false }
            ]
          },
          "similar": {
            "results": [
              { "id": 2201, "name": "Dollhouse", "first_air_date": "2009-02-13", "poster_path": "/dollhouse.jpg" }
            ]
          }
        }
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let metadata = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:show:seriesguide:show:tvdb:332331")
        metadata.setValue(Data(tmdbRawJSON.utf8), forKey: "rawJSON")
        try controller.container.viewContext.save()

        let snapshot = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .snapshot(localID: "seriesguide:show:tvdb:332331", kind: .show)
        )

        #expect(snapshot.cast.map(\.name) == ["Joel Kinnaman", "Martha Higareda"])
        #expect(snapshot.cast.first?.role == "Takeshi Kovacs")
        #expect(snapshot.cast.first?.imageURL?.absoluteString == "https://image.tmdb.org/t/p/w500/joel.jpg")
        #expect(snapshot.crew.map(\.name) == ["Laeta Kalogridis"])
        #expect(snapshot.videos.map(\.title) == ["Official Trailer"])
        #expect(snapshot.videos.first?.url.absoluteString == "https://www.youtube.com/watch?v=abc123")
        #expect(snapshot.similarItems.map(\.title) == ["Dollhouse"])
        #expect(snapshot.similarItems.first?.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/dollhouse.jpg")
    }

    @Test
    func episodeDetailSnapshotResolvesFromRouteParts() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "poster": "/show-poster.jpg",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "overview": "Needlecast trouble.", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let episode = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .episodeSnapshot(showLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 2)
        )

        #expect(episode.showTitle == "Altered Carbon")
        #expect(episode.titleLine == "1x02 Fallen Angel")
        #expect(episode.overview == "Needlecast trouble.")
        #expect(episode.artworkBackgroundURL?.absoluteString == "https://image.tmdb.org/t/p/w500/show-poster.jpg")
        #expect(episode.isWatched == false)
        #expect(episode.accessibilityLabel.contains("332331") == false)
        #expect(episode.accessibilityLabel.contains("1401624") == false)
    }

    @Test
    func episodeDetailCanResolveNextEpisodeAfterCurrentEpisode() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "poster": "/show-poster.jpg",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "first_aired": 1600000000000, "watched": true, "plays": 1 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "first_aired": 1600000000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 1401625, "episode": 3, "title": "Fresh Upload", "first_aired": 1600000000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let builder = MediaDetailSnapshotBuilder(context: controller.container.viewContext)

        let nextAfterFirst = try #require(
            builder.nextEpisode(afterShowLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 1)
        )
        #expect(nextAfterFirst.titleLine == "1x02 Fallen Angel")

        let nextAfterSecond = try #require(
            builder.nextEpisode(afterShowLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 2)
        )
        #expect(nextAfterSecond.titleLine == "1x03 Fresh Upload")

        #expect(
            builder.nextEpisode(afterShowLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 3) == nil
        )
    }

    @Test
    func unwatchedEpisodeDisplayCanHideSpoilers() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "overview": "Needlecast trouble.", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let episode = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .episodeSnapshot(showLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 2)
        )

        #expect(episode.displayTitleLine(hideSpoilers: false) == "1x02 Fallen Angel")
        #expect(episode.displayTitleLine(hideSpoilers: true) == "1x02")
        #expect(episode.displayOverview(hideSpoilers: true) == "Episode summary hidden until watched.")
    }

    @Test
    func watchedUpToMarksEarlierEpisodesAndUpdatesShowProgress() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "first_aired": 1600000000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "first_aired": 1600000000000, "watched": false, "plays": 0 },
                  { "tmdb_id": 1401625, "episode": 3, "title": "Fresh Upload", "first_aired": 1600000000000, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        try WatchStateStore(context: controller.container.viewContext, now: fixedDate)
            .markEpisodesWatchedUpTo(showLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 2)

        let snapshot = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .snapshot(localID: "seriesguide:show:tvdb:332331", kind: .show)
        )

        #expect(snapshot.item.watchCount == 2)
        #expect(snapshot.item.statusLabel == "Watching")
        #expect(snapshot.episodes.map(\.isWatched) == [true, true, false])
        #expect(snapshot.nextEpisode?.titleLine == "1x03 Fresh Upload")
    }

    @Test
    func seasonBulkActionsUpdateEpisodesAndShowProgress() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "episode": 1, "title": "Out of the Past", "watched": false, "plays": 0 },
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": false, "plays": 0 }
                ]
              },
              {
                "season": 2,
                "episodes": [
                  { "tmdb_id": 220001, "episode": 1, "title": "Phantom Lady", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(json.utf8))
        let store = WatchStateStore(context: controller.container.viewContext, now: fixedDate)
        try store.setSeasonWatched(showLocalID: "seriesguide:show:tvdb:332331", season: 1, isWatched: true)
        try store.setSeasonCollected(showLocalID: "seriesguide:show:tvdb:332331", season: 2, isCollected: true)

        let snapshot = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .snapshot(localID: "seriesguide:show:tvdb:332331", kind: .show)
        )

        #expect(snapshot.item.watchCount == 2)
        #expect(snapshot.episodes.filter { $0.seasonNumber == 1 }.map(\.isWatched) == [true, true])
        #expect(snapshot.episodes.filter { $0.seasonNumber == 2 }.map(\.isCollected) == [true])
    }

    @Test
    func movieWatchAndFavoriteActionsUpdateDetailSnapshot() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 19913,
            "imdb_id": "tt1022603",
            "title": "(500) Days of Summer",
            "overview": "A romance is remembered.",
            "watched": false,
            "plays": 0,
            "in_watchlist": false,
            "poster": "/movie.jpg"
          }
        ]
        """

        _ = try service.importBackup(data: Data(json.utf8))
        let store = WatchStateStore(
            context: controller.container.viewContext,
            now: { Date(timeIntervalSince1970: 1_700_400_000) }
        )
        try store.markMovieWatched(localID: "seriesguide:movie:tmdb:19913")
        try store.toggleFavorite(localID: "seriesguide:movie:tmdb:19913", kind: .movie)

        let snapshot = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .snapshot(localID: "seriesguide:movie:tmdb:19913", kind: .movie)
        )

        #expect(snapshot.title == "(500) Days of Summer")
        #expect(snapshot.item.statusLabel == "Watched")
        #expect(snapshot.item.watchCount == 1)
        #expect(snapshot.item.isFavorite)
        #expect(snapshot.item.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/movie.jpg")
    }

    @Test
    func movieUnwatchAndCollectionActionsUpdateDetailSnapshot() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 19913,
            "title": "(500) Days of Summer",
            "watched": true,
            "plays": 1,
            "in_watchlist": false,
            "in_collection": false
          }
        ]
        """

        _ = try service.importBackup(data: Data(json.utf8))
        let store = WatchStateStore(context: controller.container.viewContext, now: fixedDate)
        try store.markMovieUnwatched(localID: "seriesguide:movie:tmdb:19913")
        try store.toggleMovieCollected(localID: "seriesguide:movie:tmdb:19913")

        let snapshot = try #require(
            MediaDetailSnapshotBuilder(context: controller.container.viewContext)
                .snapshot(localID: "seriesguide:movie:tmdb:19913", kind: .movie)
        )

        #expect(snapshot.item.statusLabel == "Unwatched")
        #expect(snapshot.item.watchCount == 0)
        #expect(snapshot.item.isCollected)
    }

    @Test
    func watchAgainIncrementsMovieAndEpisodePlayCounts() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let showsJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": true, "plays": 1 }
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
            "title": "(500) Days of Summer",
            "watched": true,
            "plays": 1,
            "in_watchlist": false
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(showsJSON.utf8))
        _ = try service.importSeriesGuideMovies(data: Data(moviesJSON.utf8))

        let store = WatchStateStore(context: controller.container.viewContext, now: fixedDate)
        try store.watchEpisodeAgain(localID: "seriesguide:episode:tmdb:1401624")
        try store.watchMovieAgain(localID: "seriesguide:movie:tmdb:19913")

        let builder = MediaDetailSnapshotBuilder(context: controller.container.viewContext)
        let episode = try #require(builder.episodeSnapshot(showLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 2))
        let movie = try #require(builder.snapshot(localID: "seriesguide:movie:tmdb:19913", kind: .movie))
        let show = try #require(builder.snapshot(localID: "seriesguide:show:tvdb:332331", kind: .show))

        #expect(episode.watchCount == 2)
        #expect(episode.stateLabel == "Watched 2x")
        #expect(movie.item.watchCount == 2)
        #expect(show.item.watchCount == 2)
    }

    @Test
    func userOwnedRatingAndNotesCanBeEditedForShowsMoviesAndEpisodes() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let showsJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": false, "plays": 0 }
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
            "title": "(500) Days of Summer",
            "watched": false,
            "plays": 0,
            "in_watchlist": true
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(showsJSON.utf8))
        _ = try service.importSeriesGuideMovies(data: Data(moviesJSON.utf8))

        let store = WatchStateStore(context: controller.container.viewContext, now: fixedDate)
        try store.updatePersonalDetails(
            localID: "seriesguide:show:tvdb:332331",
            kind: .show,
            userRating: 8,
            notes: "Show note"
        )
        try store.updatePersonalDetails(
            localID: "seriesguide:movie:tmdb:19913",
            kind: .movie,
            userRating: 7,
            notes: "Movie note"
        )
        try store.updateEpisodePersonalDetails(
            localID: "seriesguide:episode:tmdb:1401624",
            userRating: 9,
            notes: "Episode note"
        )

        let builder = MediaDetailSnapshotBuilder(context: controller.container.viewContext)
        let show = try #require(builder.snapshot(localID: "seriesguide:show:tvdb:332331", kind: .show))
        let movie = try #require(builder.snapshot(localID: "seriesguide:movie:tmdb:19913", kind: .movie))
        let episode = try #require(builder.episodeSnapshot(showLocalID: "seriesguide:show:tvdb:332331", season: 1, episode: 2))

        #expect(show.userRating == 8)
        #expect(show.notes == "Show note")
        #expect(movie.userRating == 7)
        #expect(movie.notes == "Movie note")
        #expect(episode.userRating == 9)
        #expect(episode.notes == "Episode note")
    }
}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private func fetchMetadataRecord(in controller: PersistenceController, cacheID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
    request.predicate = NSPredicate(format: "cacheID == %@", cacheID)

    return try #require(controller.container.viewContext.fetch(request).first)
}
