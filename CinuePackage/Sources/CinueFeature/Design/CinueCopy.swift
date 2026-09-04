enum CinueCopy {
    enum State {
        static let watched = "Watched"
        static let unwatched = "Unwatched"
        static let skipped = "Skipped"
        static let inCollection = "In Collection"
        static let onWatchlist = "On Watchlist"
        static let markWatchedAction = "Mark Watched"
        static let markUnwatchedAction = "Mark Unwatched"
        static let watchAgainAction = "Watch Again"
        static let addToFavoritesAction = "Add to Favorites"
        static let removeFromFavoritesAction = "Remove from Favorites"
        static let hideFromLibraryAction = "Hide from Library"
        static let showInLibraryAction = "Show in Library"
    }

    enum EpisodeDetail {
        static let sectionTitle = "Episode Details"
        static let summaryTitle = "Episode Summary"
        static let unwatchAction = State.markUnwatchedAction
        static let skipAction = "Skip"
        static let unskipAction = "Remove Skip"
        static let addToCollectionAction = "Add to Collection"
        static let removeFromCollectionAction = "Remove from Collection"
        static let addedToCollection = "Added to Collection."
        static let removedFromCollection = "Removed from Collection."
    }

    enum ShowDetail {
        static let nextSectionTitle = "Next Episode"
        static let summaryTitle = "Show Summary"
        static let notesTitle = "Your Notes"
        static let noReleasedNextEpisode = "No released unwatched episode available."
    }

    enum MovieDetail {
        static let summaryTitle = "Movie Summary"
        static let addToWatchlistAction = "Add to Watchlist"
        static let removeFromWatchlistAction = "Remove from Watchlist"
        static let addedToWatchlist = "Added to Watchlist."
        static let removedFromWatchlist = "Removed from Watchlist."
        static let addedToCollection = EpisodeDetail.addedToCollection
        static let removedFromCollection = EpisodeDetail.removedFromCollection
    }

    enum Now {
        static let upNextEmpty = "No released unwatched episodes."
        static let historyEmpty = "Episodes you mark watched will appear here."
        static let recentEmpty = "Released unwatched episodes will appear here."
        static let upcomingEmpty = "Upcoming episodes will appear here when air dates are available."
    }

    enum Library {
        static let emptyMessage = "Shows and movies you add or import will appear here."
        static let addedToFavorites = "Added to Favorites."
        static let removedFromFavorites = "Removed from Favorites."
        static let hiddenFromLibrary = "Hidden from Library."

        static func noReleasedNextEpisode(_ title: String) -> String {
            "No released unwatched episode for \(title)."
        }
    }

    enum Discover {
        static let emptyTitle = "Find a Show or Movie"
        static let emptyMessage = "Search by title to add it to your library or watchlist."
        static let noResultsTitle = "No Matches"
        static let noResultsMessage = "Check the title or try a different search."
        static let addedToLibrary = "Added to Library."
        static let addedToWatchlist = MovieDetail.addedToWatchlist
        static let onWatchlist = State.onWatchlist
        static let inLibrary = "In Library"
    }

    enum Lists {
        static let emptyMessage = "Your watchlist and custom lists will appear here."
        static let emptyListMessage = "Shows and movies added to this list will appear here."
        static let unresolvedItemMessage = "Import the matching show or movie to show this item."
    }

    enum Settings {
        static let importExportIntro = "Export Cinue backups for Cinue. Import Cinue or SeriesGuide JSON backups when restoring or migrating."
        static let importSourceHelp = "Choose a Cinue backup or SeriesGuide JSON backup. Cinue imports supported shows, movies, lists, and watch history."
        static let importProgress = "Importing backup. You can leave this screen."
        static let importStarted = "Import started. You can leave this screen while Cinue processes the file."
        static let importFailure = "Import failed. Choose a Cinue backup or supported SeriesGuide JSON file."
        static let exportPreparing = "Preparing backup export."
        static let exportSuccess = "Export saved."
        static let exportFailure = "Export was not saved. Try again or choose another location."
        static let seriesGuideImportCompatibility = "SeriesGuide JSON import supports backups exported from SeriesGuide."
        static let iCloudUnavailableReason = "Requires Apple Developer Program capabilities"
        static let iCloudExplanation = "iCloud auto sync requires app iCloud capabilities configured through Apple Developer Program membership. Manual backups work without it."
        static let privacyLocalStorage = "Watch state, favorites, ratings, notes, and imported backups stay on this device unless you export a file yourself."
    }

    enum Insights {
        static let withReleasedNextEpisodes = "With Released Next Episodes"
        static let finishedWatching = "Finished Watching"
        static let watchTime = "Watch Time"
        static let watchlistRuntime = "Watchlist Runtime"
        static let collectionRuntime = "Collection Runtime"
    }
}
