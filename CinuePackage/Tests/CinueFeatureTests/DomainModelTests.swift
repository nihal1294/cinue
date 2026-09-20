import Foundation
import Testing
@testable import CinueFeature

struct DomainModelTests {
    @Test
    func contentIDsAreProviderNeutral() {
        let ids = ContentIDs(localID: "local-1", tvdbID: 123, tmdbID: 456, imdbID: "tt123", traktID: nil)

        #expect(ids.localID == "local-1")
        #expect(ids.tvdbID == 123)
        #expect(ids.tmdbID == 456)
        #expect(ids.imdbID == "tt123")
        #expect(ids.traktID == nil)
    }

    @Test
    func contentIDsGenerateLocalIDWhenNeeded() {
        let ids = ContentIDs()

        #expect(ids.localID.isEmpty == false)
        #expect(ids.tvdbID == nil)
        #expect(ids.tmdbID == nil)
        #expect(ids.imdbID == nil)
        #expect(ids.traktID == nil)
    }

    @Test
    func mediaSummaryUsesLocalIDForStableIdentity() throws {
        let posterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))
        let summary = MediaSummary(
            contentIDs: ContentIDs(localID: "show-1", tvdbID: 100, tmdbID: 200),
            kind: .show,
            title: "Example Show",
            originalTitle: nil,
            overview: "A provider-neutral summary.",
            releaseDate: nil,
            posterURL: posterURL,
            backdropURL: nil,
            attribution: .theTVDB
        )

        #expect(summary.id == "show-1")
        #expect(summary.kind == .show)
        #expect(summary.title == "Example Show")
        #expect(summary.posterURL == posterURL)
        #expect(summary.attribution.providerID == .theTVDB)
    }

    @Test
    func watchStateDefaultsToUnwatched() {
        let state = UserWatchState()

        #expect(state.status == .unwatched)
        #expect(state.watchCount == 0)
        #expect(state.watchedAt == nil)
        #expect(state.isFavorite == false)
        #expect(state.isHidden == false)
        #expect(state.userRating == nil)
        #expect(state.notes == "")
    }

    @Test
    func providerAttributionIncludesRequiredTMDBLanguage() {
        let attribution = ProviderAttribution.tmdb

        #expect(attribution.providerID == .tmdb)
        #expect(attribution.providerName == "TMDB")
        #expect(attribution.requiredText == "This product uses the TMDB API but is not endorsed or certified by TMDB.")
        #expect(attribution.sourceURL?.host() == "www.themoviedb.org")
    }
}
