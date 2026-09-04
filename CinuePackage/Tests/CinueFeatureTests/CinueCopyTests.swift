import Testing
@testable import CinueFeature

struct CinueCopyTests {
    @Test
    func approvedDetailCopyMatchesAudit() {
        #expect(CinueCopy.EpisodeDetail.sectionTitle == "Episode Details")
        #expect(CinueCopy.EpisodeDetail.unwatchAction == "Mark Unwatched")
        #expect(CinueCopy.EpisodeDetail.unskipAction == "Remove Skip")
        #expect(CinueCopy.EpisodeDetail.addToCollectionAction == "Add to Collection")
        #expect(CinueCopy.EpisodeDetail.removeFromCollectionAction == "Remove from Collection")
        #expect(CinueCopy.EpisodeDetail.summaryTitle == "Episode Summary")

        #expect(CinueCopy.ShowDetail.nextSectionTitle == "Next Episode")
        #expect(CinueCopy.ShowDetail.summaryTitle == "Show Summary")
        #expect(CinueCopy.ShowDetail.noReleasedNextEpisode == "No released unwatched episode available.")

        #expect(CinueCopy.MovieDetail.summaryTitle == "Movie Summary")
        #expect(CinueCopy.MovieDetail.addToWatchlistAction == "Add to Watchlist")
        #expect(CinueCopy.MovieDetail.removeFromWatchlistAction == "Remove from Watchlist")
    }

    @Test
    func approvedStateAndEmptyCopyMatchesAudit() {
        #expect(CinueCopy.State.inCollection == "In Collection")
        #expect(CinueCopy.State.onWatchlist == "On Watchlist")
        #expect(CinueCopy.State.watchAgainAction == "Watch Again")
        #expect(CinueCopy.State.addToFavoritesAction == "Add to Favorites")
        #expect(CinueCopy.State.removeFromFavoritesAction == "Remove from Favorites")

        #expect(CinueCopy.Now.upNextEmpty == "No released unwatched episodes.")
        #expect(CinueCopy.Now.historyEmpty == "Episodes you mark watched will appear here.")
        #expect(CinueCopy.Now.recentEmpty == "Released unwatched episodes will appear here.")
        #expect(CinueCopy.Now.upcomingEmpty == "Upcoming episodes will appear here when air dates are available.")

        #expect(CinueCopy.Library.emptyMessage == "Shows and movies you add or import will appear here.")
        #expect(CinueCopy.Library.noReleasedNextEpisode("Severance") == "No released unwatched episode for Severance.")
        #expect(CinueCopy.Library.addedToFavorites == "Added to Favorites.")
        #expect(CinueCopy.Library.removedFromFavorites == "Removed from Favorites.")
        #expect(CinueCopy.Library.hiddenFromLibrary == "Hidden from Library.")

        #expect(CinueCopy.Discover.emptyTitle == "Find a Show or Movie")
        #expect(CinueCopy.Discover.emptyMessage == "Search by title to add it to your library or watchlist.")
        #expect(CinueCopy.Discover.noResultsTitle == "No Matches")
        #expect(CinueCopy.Discover.noResultsMessage == "Check the title or try a different search.")

        #expect(CinueCopy.Lists.emptyMessage == "Your watchlist and custom lists will appear here.")
        #expect(CinueCopy.Lists.emptyListMessage == "Shows and movies added to this list will appear here.")
        #expect(CinueCopy.Lists.unresolvedItemMessage == "Import the matching show or movie to show this item.")
    }

    @Test
    func approvedSettingsAndInsightsCopyMatchesAudit() {
        #expect(CinueCopy.Settings.importExportIntro == "Export Cinue backups for Cinue. Import Cinue or SeriesGuide JSON backups when restoring or migrating.")
        #expect(CinueCopy.Settings.importSourceHelp == "Choose a Cinue backup or SeriesGuide JSON backup. Cinue imports supported shows, movies, lists, and watch history.")
        #expect(CinueCopy.Settings.importProgress == "Importing backup. You can leave this screen.")
        #expect(CinueCopy.Settings.importFailure == "Import failed. Choose a Cinue backup or supported SeriesGuide JSON file.")
        #expect(CinueCopy.Settings.exportPreparing == "Preparing backup export.")
        #expect(CinueCopy.Settings.exportSuccess == "Export saved.")
        #expect(CinueCopy.Settings.exportFailure == "Export was not saved. Try again or choose another location.")
        #expect(CinueCopy.Settings.seriesGuideImportCompatibility == "SeriesGuide JSON import supports backups exported from SeriesGuide.")
        #expect(CinueCopy.Settings.iCloudUnavailableReason == "Requires Apple Developer Program capabilities")
        #expect(CinueCopy.Settings.iCloudExplanation == "iCloud auto sync requires app iCloud capabilities configured through Apple Developer Program membership. Manual backups work without it.")
        #expect(CinueCopy.Settings.privacyLocalStorage == "Watch state, favorites, ratings, notes, and imported backups stay on this device unless you export a file yourself.")

        #expect(CinueCopy.Insights.withReleasedNextEpisodes == "With Released Next Episodes")
        #expect(CinueCopy.Insights.finishedWatching == "Finished Watching")
        #expect(CinueCopy.Insights.watchTime == "Watch Time")
        #expect(CinueCopy.Insights.watchlistRuntime == "Watchlist Runtime")
        #expect(CinueCopy.Insights.collectionRuntime == "Collection Runtime")
    }
}
