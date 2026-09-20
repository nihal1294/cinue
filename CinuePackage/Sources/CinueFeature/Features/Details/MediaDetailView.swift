import CoreData
import SwiftUI

struct ShowDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var trackedItems: FetchedResults<NSManagedObject>
    @FetchRequest private var episodeStates: FetchedResults<NSManagedObject>
    @FetchRequest private var userLists: FetchedResults<NSManagedObject>
    @State private var actionMessage: String?
    @State private var actionRoute: Route?
    @State private var isEditingPersonalDetails = false
    @State private var isManagingLists = false
    @State private var isConfirmingRemoval = false

    private let localID: String

    init(localID: String) {
        self.localID = localID

        let itemRequest = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        itemRequest.predicate = NSPredicate(format: "localID == %@", localID)
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        _trackedItems = FetchRequest(fetchRequest: itemRequest, animation: .default)

        let episodeRequest = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        episodeRequest.predicate = NSPredicate(format: "showLocalID == %@", localID)
        episodeRequest.sortDescriptors = [
            NSSortDescriptor(key: "seasonNumber", ascending: true),
            NSSortDescriptor(key: "episodeNumber", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]
        _episodeStates = FetchRequest(fetchRequest: episodeRequest, animation: .default)

        let listRequest = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        listRequest.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        _userLists = FetchRequest(fetchRequest: listRequest, animation: .default)
    }

    var body: some View {
        Group {
            if let snapshot {
                MediaDetailContent(
                    snapshot: snapshot,
                    actionMessage: actionMessage,
                    actionRoute: actionRoute,
                    markNextWatchedAction: {
                        markNextWatched(snapshot)
                    },
                    markMovieUnwatchedAction: nil,
                    markMovieWatchedAction: nil,
                    watchMovieAgainAction: nil,
                    toggleMovieCollectedAction: nil,
                    toggleFavoriteAction: {
                        toggleFavorite(snapshot)
                    },
                    toggleHiddenAction: {
                        toggleHidden(snapshot)
                    },
                    manageListsAction: {
                        isManagingLists = true
                    },
                    refreshMetadataAction: {
                        refreshMetadata(snapshot)
                    },
                    removeFromLibraryAction: {
                        isConfirmingRemoval = true
                    },
                    editPersonalDetailsAction: {
                        isEditingPersonalDetails = true
                    },
                    markEpisodeWatchedAction: { episode in
                        markEpisodeWatched(episode)
                    },
                    watchEpisodeAgainAction: { episode in
                        watchEpisodeAgain(episode)
                    },
                    markEpisodeUnwatchedAction: { episode in
                        markEpisodeUnwatched(episode)
                    },
                    markEpisodeWatchedUpToAction: { episode in
                        markEpisodeWatchedUpTo(episode)
                    },
                    toggleEpisodeSkippedAction: { episode in
                        toggleEpisodeSkipped(episode)
                    },
                    toggleEpisodeCollectedAction: { episode in
                        toggleEpisodeCollected(episode)
                    },
                    setShowWatchedAction: { isWatched in
                        setShowWatched(snapshot, isWatched: isWatched)
                    },
                    setShowCollectedAction: { isCollected in
                        setShowCollected(snapshot, isCollected: isCollected)
                    },
                    setSeasonWatchedAction: { season, isWatched in
                        setSeasonWatched(season, isWatched: isWatched)
                    },
                    setSeasonCollectedAction: { season, isCollected in
                        setSeasonCollected(season, isCollected: isCollected)
                    },
                    setSeasonSkippedAction: { season, isSkipped in
                        setSeasonSkipped(season, isSkipped: isSkipped)
                    }
                )
            } else {
                CinueDetailMissingView(title: "Show Not Found")
            }
        }
        .background {
            if let snapshot {
                CinueArtworkBackground(
                    backdropURL: snapshot.backdropURL,
                    posterURL: snapshot.item.posterURL,
                    kind: snapshot.item.kind,
                    fallbackTone: .primary
                )
            } else {
                backgroundColor.ignoresSafeArea()
            }
        }
        .navigationTitle(snapshot?.title ?? "Show")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingPersonalDetails) {
            if let snapshot {
                PersonalDetailsEditorSheet(
                    title: snapshot.title,
                    userRating: snapshot.userRating,
                    notes: snapshot.notes,
                    onSave: { userRating, notes in
                        updatePersonalDetails(snapshot, userRating: userRating, notes: notes)
                    }
                )
            }
        }
        .sheet(isPresented: $isManagingLists) {
            if let snapshot {
                ManageListsSheet(
                    itemTitle: snapshot.title,
                    rows: listMembershipRows(for: snapshot.item),
                    toggleAction: { row in
                        setListMembership(row, for: snapshot.item)
                    }
                )
            }
        }
        .alert("Remove from Library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removeFromLibrary()
            }
        } message: {
            Text("This removes local watch state, notes, and list membership for this show.")
        }
        .cinueAutoDismissFeedback($actionMessage, after: CinueTransientFeedback.actionableDisplayDuration)
    }

    private var snapshot: MediaDetailSnapshot? {
        _ = trackedItems.count
        _ = episodeStates.count
        return MediaDetailSnapshotBuilder(context: viewContext).snapshot(localID: localID, kind: .show)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private func markNextWatched(_ snapshot: MediaDetailSnapshot) {
        guard let nextEpisode = snapshot.nextEpisode else {
            actionMessage = CinueCopy.ShowDetail.noReleasedNextEpisode
            actionRoute = nil
            return
        }

        markEpisodeWatched(nextEpisode)
    }

    private func markEpisodeWatched(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markEpisodeWatched(localID: episode.localID)
            actionMessage = "\(episode.titleLine) marked watched."
            actionRoute = nextEpisodeRoute(after: episode)
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func watchEpisodeAgain(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).watchEpisodeAgain(localID: episode.localID)
            actionMessage = "\(episode.titleLine) watched again."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func markEpisodeUnwatched(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markEpisodeUnwatched(localID: episode.localID)
            actionMessage = "\(episode.titleLine) marked unwatched."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func markEpisodeWatchedUpTo(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext)
                .markEpisodesWatchedUpTo(
                    showLocalID: episode.showLocalID,
                    season: episode.seasonNumber,
                    episode: episode.episodeNumber ?? 0
                )
            actionMessage = "Marked watched up to \(episode.titleLine)."
            actionRoute = nextEpisodeRoute(after: episode)
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func toggleEpisodeSkipped(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleEpisodeSkipped(localID: episode.localID)
            actionMessage = episode.isSkipped ? "\(episode.titleLine) unskipped." : "\(episode.titleLine) skipped."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update skip state."
            actionRoute = nil
        }
    }

    private func toggleEpisodeCollected(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleEpisodeCollected(localID: episode.localID)
            actionMessage = episode.isCollected ? CinueCopy.EpisodeDetail.removedFromCollection : CinueCopy.EpisodeDetail.addedToCollection
            actionRoute = nil
        } catch {
            actionMessage = "Could not update collection."
            actionRoute = nil
        }
    }

    private func setShowWatched(_ snapshot: MediaDetailSnapshot, isWatched: Bool) {
        do {
            try WatchStateStore(context: viewContext).setShowWatched(showLocalID: snapshot.id, isWatched: isWatched)
            actionMessage = isWatched ? "Show marked watched." : "Show marked unwatched."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update show."
            actionRoute = nil
        }
    }

    private func setShowCollected(_ snapshot: MediaDetailSnapshot, isCollected: Bool) {
        do {
            try WatchStateStore(context: viewContext).setShowCollected(showLocalID: snapshot.id, isCollected: isCollected)
            actionMessage = isCollected ? "Show added to collection." : "Show removed from collection."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update collection."
            actionRoute = nil
        }
    }

    private func setSeasonWatched(_ season: SeasonDetailSnapshot, isWatched: Bool) {
        guard let firstEpisode = season.episodes.first else {
            return
        }

        do {
            try WatchStateStore(context: viewContext)
                .setSeasonWatched(showLocalID: firstEpisode.showLocalID, season: season.seasonNumber, isWatched: isWatched)
            actionMessage = isWatched ? "\(season.title) marked watched." : "\(season.title) marked unwatched."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update season."
            actionRoute = nil
        }
    }

    private func setSeasonCollected(_ season: SeasonDetailSnapshot, isCollected: Bool) {
        guard let firstEpisode = season.episodes.first else {
            return
        }

        do {
            try WatchStateStore(context: viewContext)
                .setSeasonCollected(showLocalID: firstEpisode.showLocalID, season: season.seasonNumber, isCollected: isCollected)
            actionMessage = isCollected ? "\(season.title) added to collection." : "\(season.title) removed from collection."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update collection."
            actionRoute = nil
        }
    }

    private func setSeasonSkipped(_ season: SeasonDetailSnapshot, isSkipped: Bool) {
        guard let firstEpisode = season.episodes.first else {
            return
        }

        do {
            try WatchStateStore(context: viewContext)
                .setSeasonSkipped(showLocalID: firstEpisode.showLocalID, season: season.seasonNumber, isSkipped: isSkipped)
            actionMessage = isSkipped ? "\(season.title) skipped." : "\(season.title) unskipped."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update season."
            actionRoute = nil
        }
    }

    private func toggleFavorite(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleFavorite(localID: snapshot.id, kind: snapshot.item.kind)
            actionMessage = snapshot.item.isFavorite ? CinueCopy.Library.removedFromFavorites : CinueCopy.Library.addedToFavorites
            actionRoute = nil
        } catch {
            actionMessage = "Could not update favorite."
            actionRoute = nil
        }
    }

    private func toggleHidden(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleHidden(localID: snapshot.id, kind: snapshot.item.kind)
            actionMessage = snapshot.isHidden ? "Shown in Library." : CinueCopy.Library.hiddenFromLibrary
            actionRoute = nil
        } catch {
            actionMessage = "Could not update visibility."
            actionRoute = nil
        }
    }

    private func updatePersonalDetails(_ snapshot: MediaDetailSnapshot, userRating: Int?, notes: String?) {
        do {
            try WatchStateStore(context: viewContext)
                .updatePersonalDetails(localID: snapshot.id, kind: snapshot.item.kind, userRating: userRating, notes: notes)
            actionMessage = "Details updated."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update details."
            actionRoute = nil
        }
    }

    private func refreshMetadata(_ snapshot: MediaDetailSnapshot) {
        actionMessage = "Refreshing \(snapshot.title)."
        actionRoute = nil
        Task {
            let summary = await environment.metadataRefreshService.refreshMetadata(localID: snapshot.id, kind: snapshot.item.kind)
            actionMessage = metadataRefreshStatusMessage(summary, title: snapshot.title)
            actionRoute = nil
        }
    }

    private func removeFromLibrary() {
        guard let snapshot else {
            return
        }

        do {
            try ContentLibraryStore(context: viewContext).removeFromLibrary(localID: snapshot.id, kind: snapshot.item.kind)
            dismiss()
        } catch {
            actionMessage = "Could not remove item."
            actionRoute = nil
        }
    }

    private func setListMembership(_ row: ListMembershipRowSnapshot, for item: LibraryItemSnapshot) {
        do {
            try ContentLibraryStore(context: viewContext)
                .setListMembership(itemLocalID: item.localID, listLocalID: row.localID, isIncluded: row.isIncluded == false)
            actionMessage = row.isIncluded ? "Removed from \(row.name)." : "Added to \(row.name)."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update list."
            actionRoute = nil
        }
    }

    private func listMembershipRows(for item: LibraryItemSnapshot) -> [ListMembershipRowSnapshot] {
        ListMembershipRowBuilder(context: viewContext)
            .rows(for: item, lists: Array(userLists))
    }

    private func nextEpisodeRoute(after episode: EpisodeDetailSnapshot) -> Route? {
        guard let nextEpisode = MediaDetailSnapshotBuilder(context: viewContext)
            .nextEpisode(
                afterShowLocalID: episode.showLocalID,
                season: episode.seasonNumber,
                episode: episode.episodeNumber ?? 0
            ),
            let nextEpisodeNumber = nextEpisode.episodeNumber
        else {
            return nil
        }

        return .episodeDetail(showID: nextEpisode.showLocalID, season: nextEpisode.seasonNumber, episode: nextEpisodeNumber)
    }
}

struct MovieDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var trackedItems: FetchedResults<NSManagedObject>
    @FetchRequest private var userLists: FetchedResults<NSManagedObject>
    @State private var actionMessage: String?
    @State private var isEditingPersonalDetails = false
    @State private var isManagingLists = false
    @State private var isConfirmingRemoval = false

    private let localID: String

    init(localID: String) {
        self.localID = localID

        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.predicate = NSPredicate(format: "localID == %@", localID)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        _trackedItems = FetchRequest(fetchRequest: request, animation: .default)

        let listRequest = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        listRequest.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        _userLists = FetchRequest(fetchRequest: listRequest, animation: .default)
    }

    var body: some View {
        Group {
            if let snapshot {
                MediaDetailContent(
                    snapshot: snapshot,
                    actionMessage: actionMessage,
                    actionRoute: nil,
                    markNextWatchedAction: nil,
                    markMovieUnwatchedAction: snapshot.item.watchCount > 0 ? {
                        markMovieUnwatched(snapshot)
                    } : nil,
                    markMovieWatchedAction: {
                        markMovieWatched(snapshot)
                    },
                    watchMovieAgainAction: snapshot.item.watchCount > 0 ? {
                        watchMovieAgain(snapshot)
                    } : nil,
                    toggleMovieCollectedAction: {
                        toggleMovieCollected(snapshot)
                    },
                    toggleFavoriteAction: {
                        toggleFavorite(snapshot)
                    },
                    toggleHiddenAction: {
                        toggleHidden(snapshot)
                    },
                    manageListsAction: {
                        isManagingLists = true
                    },
                    refreshMetadataAction: {
                        refreshMetadata(snapshot)
                    },
                    removeFromLibraryAction: {
                        isConfirmingRemoval = true
                    },
                    editPersonalDetailsAction: {
                        isEditingPersonalDetails = true
                    },
                    markEpisodeWatchedAction: nil,
                    watchEpisodeAgainAction: nil,
                    markEpisodeUnwatchedAction: nil,
                    markEpisodeWatchedUpToAction: nil,
                    toggleEpisodeSkippedAction: nil,
                    toggleEpisodeCollectedAction: nil,
                    setShowWatchedAction: nil,
                    setShowCollectedAction: nil,
                    setSeasonWatchedAction: nil,
                    setSeasonCollectedAction: nil,
                    setSeasonSkippedAction: nil
                )
            } else {
                CinueDetailMissingView(title: "Movie Not Found")
            }
        }
        .background {
            if let snapshot {
                CinueArtworkBackground(
                    backdropURL: snapshot.backdropURL,
                    posterURL: snapshot.item.posterURL,
                    kind: snapshot.item.kind,
                    fallbackTone: .metadata
                )
            } else {
                backgroundColor.ignoresSafeArea()
            }
        }
        .navigationTitle(snapshot?.title ?? "Movie")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingPersonalDetails) {
            if let snapshot {
                PersonalDetailsEditorSheet(
                    title: snapshot.title,
                    userRating: snapshot.userRating,
                    notes: snapshot.notes,
                    onSave: { userRating, notes in
                        updatePersonalDetails(snapshot, userRating: userRating, notes: notes)
                    }
                )
            }
        }
        .sheet(isPresented: $isManagingLists) {
            if let snapshot {
                ManageListsSheet(
                    itemTitle: snapshot.title,
                    rows: listMembershipRows(for: snapshot.item),
                    toggleAction: { row in
                        setListMembership(row, for: snapshot.item)
                    }
                )
            }
        }
        .alert("Remove from Library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removeFromLibrary()
            }
        } message: {
            Text("This removes local watch state, notes, and list membership for this movie.")
        }
        .cinueAutoDismissFeedback($actionMessage, after: CinueTransientFeedback.actionableDisplayDuration)
    }

    private var snapshot: MediaDetailSnapshot? {
        _ = trackedItems.count
        return MediaDetailSnapshotBuilder(context: viewContext).snapshot(localID: localID, kind: .movie)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private func markMovieWatched(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markMovieWatched(localID: snapshot.id)
            actionMessage = "\(snapshot.title) marked watched."
        } catch {
            actionMessage = "Could not update watch state."
        }
    }

    private func watchMovieAgain(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).watchMovieAgain(localID: snapshot.id)
            actionMessage = "\(snapshot.title) watched again."
        } catch {
            actionMessage = "Could not update watch state."
        }
    }

    private func markMovieUnwatched(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markMovieUnwatched(localID: snapshot.id)
            actionMessage = "\(snapshot.title) marked unwatched."
        } catch {
            actionMessage = "Could not update watch state."
        }
    }

    private func toggleMovieCollected(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleMovieCollected(localID: snapshot.id)
            actionMessage = snapshot.item.isCollected ? CinueCopy.MovieDetail.removedFromCollection : CinueCopy.MovieDetail.addedToCollection
        } catch {
            actionMessage = "Could not update collection."
        }
    }

    private func toggleFavorite(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleFavorite(localID: snapshot.id, kind: snapshot.item.kind)
            actionMessage = snapshot.item.isFavorite ? CinueCopy.MovieDetail.removedFromWatchlist : CinueCopy.MovieDetail.addedToWatchlist
        } catch {
            actionMessage = "Could not update watchlist."
        }
    }

    private func toggleHidden(_ snapshot: MediaDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleHidden(localID: snapshot.id, kind: snapshot.item.kind)
            actionMessage = snapshot.isHidden ? "Shown in Library." : CinueCopy.Library.hiddenFromLibrary
        } catch {
            actionMessage = "Could not update visibility."
        }
    }

    private func updatePersonalDetails(_ snapshot: MediaDetailSnapshot, userRating: Int?, notes: String?) {
        do {
            try WatchStateStore(context: viewContext)
                .updatePersonalDetails(localID: snapshot.id, kind: snapshot.item.kind, userRating: userRating, notes: notes)
            actionMessage = "Details updated."
        } catch {
            actionMessage = "Could not update details."
        }
    }

    private func refreshMetadata(_ snapshot: MediaDetailSnapshot) {
        actionMessage = "Refreshing \(snapshot.title)."
        Task {
            let summary = await environment.metadataRefreshService.refreshMetadata(localID: snapshot.id, kind: snapshot.item.kind)
            actionMessage = metadataRefreshStatusMessage(summary, title: snapshot.title)
        }
    }

    private func removeFromLibrary() {
        guard let snapshot else {
            return
        }

        do {
            try ContentLibraryStore(context: viewContext).removeFromLibrary(localID: snapshot.id, kind: snapshot.item.kind)
            dismiss()
        } catch {
            actionMessage = "Could not remove item."
        }
    }

    private func setListMembership(_ row: ListMembershipRowSnapshot, for item: LibraryItemSnapshot) {
        do {
            try ContentLibraryStore(context: viewContext)
                .setListMembership(itemLocalID: item.localID, listLocalID: row.localID, isIncluded: row.isIncluded == false)
            actionMessage = row.isIncluded ? "Removed from \(row.name)." : "Added to \(row.name)."
        } catch {
            actionMessage = "Could not update list."
        }
    }

    private func listMembershipRows(for item: LibraryItemSnapshot) -> [ListMembershipRowSnapshot] {
        ListMembershipRowBuilder(context: viewContext)
            .rows(for: item, lists: Array(userLists))
    }
}

struct EpisodeDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @FetchRequest private var episodeStates: FetchedResults<NSManagedObject>
    @State private var actionMessage: String?
    @State private var actionRoute: Route?
    @State private var isEditingPersonalDetails = false

    private let showID: String
    private let season: Int
    private let episode: Int

    init(showID: String, season: Int, episode: Int) {
        self.showID = showID
        self.season = season
        self.episode = episode

        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.predicate = NSPredicate(format: "showLocalID == %@", showID)
        request.sortDescriptors = [
            NSSortDescriptor(key: "seasonNumber", ascending: true),
            NSSortDescriptor(key: "episodeNumber", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]
        _episodeStates = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        Group {
            if let snapshot {
                EpisodeDetailContent(
                    episode: snapshot,
                    actionMessage: actionMessage,
                    actionRoute: actionRoute,
                    markWatchedAction: {
                        markWatched(snapshot)
                    },
                    watchAgainAction: {
                        watchAgain(snapshot)
                    },
                    markUnwatchedAction: {
                        markUnwatched(snapshot)
                    },
                    toggleSkippedAction: {
                        toggleSkipped(snapshot)
                    },
                    markWatchedUpToAction: {
                        markWatchedUpTo(snapshot)
                    },
                    toggleCollectedAction: {
                        toggleCollected(snapshot)
                    },
                    editPersonalDetailsAction: {
                        isEditingPersonalDetails = true
                    }
                )
            } else {
                CinueDetailMissingView(title: "Episode Not Found")
            }
        }
        .background {
            if let snapshot {
                CinueArtworkBackground(
                    backdropURL: snapshot.backdropURL,
                    posterURL: snapshot.artworkBackgroundURL,
                    kind: .show,
                    fallbackTone: snapshot.isWatched ? .privacy : .primary
                )
            } else {
                backgroundColor.ignoresSafeArea()
            }
        }
        .navigationTitle(snapshot?.showTitle ?? "Episode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingPersonalDetails) {
            if let snapshot {
                PersonalDetailsEditorSheet(
                    title: snapshot.titleLine,
                    userRating: snapshot.userRating,
                    notes: snapshot.notes,
                    onSave: { userRating, notes in
                        updatePersonalDetails(snapshot, userRating: userRating, notes: notes)
                    }
                )
            }
        }
        .cinueAutoDismissFeedback($actionMessage, after: CinueTransientFeedback.actionableDisplayDuration)
    }

    private var snapshot: EpisodeDetailSnapshot? {
        _ = episodeStates.count
        return MediaDetailSnapshotBuilder(context: viewContext)
            .episodeSnapshot(showLocalID: showID, season: season, episode: episode)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private func markWatched(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markEpisodeWatched(localID: episode.localID)
            actionMessage = "\(episode.titleLine) marked watched."
            actionRoute = nextEpisodeRoute(after: episode)
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func watchAgain(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).watchEpisodeAgain(localID: episode.localID)
            actionMessage = "\(episode.titleLine) watched again."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func markUnwatched(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markEpisodeUnwatched(localID: episode.localID)
            actionMessage = "\(episode.titleLine) marked unwatched."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func markWatchedUpTo(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext)
                .markEpisodesWatchedUpTo(
                    showLocalID: episode.showLocalID,
                    season: episode.seasonNumber,
                    episode: episode.episodeNumber ?? 0
                )
            actionMessage = "Marked watched up to \(episode.titleLine)."
            actionRoute = nextEpisodeRoute(after: episode)
        } catch {
            actionMessage = "Could not update watch state."
            actionRoute = nil
        }
    }

    private func toggleSkipped(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleEpisodeSkipped(localID: episode.localID)
            actionMessage = episode.isSkipped ? "\(episode.titleLine) unskipped." : "\(episode.titleLine) skipped."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update skip state."
            actionRoute = nil
        }
    }

    private func toggleCollected(_ episode: EpisodeDetailSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleEpisodeCollected(localID: episode.localID)
            actionMessage = episode.isCollected ? CinueCopy.EpisodeDetail.removedFromCollection : CinueCopy.EpisodeDetail.addedToCollection
            actionRoute = nil
        } catch {
            actionMessage = "Could not update collection."
            actionRoute = nil
        }
    }

    private func updatePersonalDetails(_ episode: EpisodeDetailSnapshot, userRating: Int?, notes: String?) {
        do {
            try WatchStateStore(context: viewContext)
                .updateEpisodePersonalDetails(localID: episode.localID, userRating: userRating, notes: notes)
            actionMessage = "Details updated."
            actionRoute = nil
        } catch {
            actionMessage = "Could not update details."
            actionRoute = nil
        }
    }

    private func nextEpisodeRoute(after episode: EpisodeDetailSnapshot) -> Route? {
        guard let nextEpisode = MediaDetailSnapshotBuilder(context: viewContext)
            .nextEpisode(
                afterShowLocalID: episode.showLocalID,
                season: episode.seasonNumber,
                episode: episode.episodeNumber ?? 0
            ),
            let nextEpisodeNumber = nextEpisode.episodeNumber
        else {
            return nil
        }

        return .episodeDetail(showID: nextEpisode.showLocalID, season: nextEpisode.seasonNumber, episode: nextEpisodeNumber)
    }
}

private struct MediaDetailContent: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: MediaDetailSnapshot
    let actionMessage: String?
    let actionRoute: Route?
    let markNextWatchedAction: (() -> Void)?
    let markMovieUnwatchedAction: (() -> Void)?
    let markMovieWatchedAction: (() -> Void)?
    let watchMovieAgainAction: (() -> Void)?
    let toggleMovieCollectedAction: (() -> Void)?
    let toggleFavoriteAction: () -> Void
    let toggleHiddenAction: () -> Void
    let manageListsAction: () -> Void
    let refreshMetadataAction: () -> Void
    let removeFromLibraryAction: () -> Void
    let editPersonalDetailsAction: () -> Void
    let markEpisodeWatchedAction: ((EpisodeDetailSnapshot) -> Void)?
    let watchEpisodeAgainAction: ((EpisodeDetailSnapshot) -> Void)?
    let markEpisodeUnwatchedAction: ((EpisodeDetailSnapshot) -> Void)?
    let markEpisodeWatchedUpToAction: ((EpisodeDetailSnapshot) -> Void)?
    let toggleEpisodeSkippedAction: ((EpisodeDetailSnapshot) -> Void)?
    let toggleEpisodeCollectedAction: ((EpisodeDetailSnapshot) -> Void)?
    let setShowWatchedAction: ((Bool) -> Void)?
    let setShowCollectedAction: ((Bool) -> Void)?
    let setSeasonWatchedAction: ((SeasonDetailSnapshot, Bool) -> Void)?
    let setSeasonCollectedAction: ((SeasonDetailSnapshot, Bool) -> Void)?
    let setSeasonSkippedAction: ((SeasonDetailSnapshot, Bool) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                MediaHero(snapshot: snapshot)

                if let actionMessage {
                    DetailMessageRow(message: actionMessage, actionRoute: actionRoute)
                }

                DetailActionGrid(
                    snapshot: snapshot,
                    markNextWatchedAction: markNextWatchedAction,
                    markMovieUnwatchedAction: markMovieUnwatchedAction,
                    markMovieWatchedAction: markMovieWatchedAction,
                    watchMovieAgainAction: watchMovieAgainAction,
                    toggleMovieCollectedAction: toggleMovieCollectedAction,
                    toggleFavoriteAction: toggleFavoriteAction,
                    toggleHiddenAction: toggleHiddenAction,
                    manageListsAction: manageListsAction,
                    refreshMetadataAction: refreshMetadataAction,
                    removeFromLibraryAction: removeFromLibraryAction,
                    editPersonalDetailsAction: editPersonalDetailsAction
                )

                if let nextEpisode = snapshot.nextEpisode {
                    DetailSection(title: CinueCopy.ShowDetail.nextSectionTitle) {
                        DetailEpisodeRow(
                            episode: nextEpisode,
                            showsWatchAction: true,
                            markWatchedAction: {
                                markEpisodeWatchedAction?(nextEpisode)
                            },
                            watchAgainAction: {
                                watchEpisodeAgainAction?(nextEpisode)
                            },
                            markUnwatchedAction: {
                                markEpisodeUnwatchedAction?(nextEpisode)
                            },
                            markWatchedUpToAction: {
                                markEpisodeWatchedUpToAction?(nextEpisode)
                            },
                            toggleSkippedAction: {
                                toggleEpisodeSkippedAction?(nextEpisode)
                            },
                            toggleCollectedAction: {
                                toggleEpisodeCollectedAction?(nextEpisode)
                            }
                        )
                    }
                }

                if let notes = snapshot.notes {
                    DetailTextSection(title: CinueCopy.ShowDetail.notesTitle, text: notes)
                }

                if let overview = snapshot.overview {
                    DetailTextSection(title: snapshot.item.kind == .movie ? CinueCopy.MovieDetail.summaryTitle : CinueCopy.ShowDetail.summaryTitle, text: overview)
                }

                if snapshot.cast.isEmpty == false {
                    DetailPeopleSection(title: "Cast", credits: snapshot.cast)
                }

                if snapshot.crew.isEmpty == false {
                    DetailPeopleSection(title: "Crew", credits: snapshot.crew)
                }

                if snapshot.videos.isEmpty == false {
                    DetailVideosSection(videos: snapshot.videos)
                }

                if snapshot.similarItems.isEmpty == false {
                    DetailSimilarItemsSection(items: snapshot.similarItems)
                }

                if snapshot.episodes.isEmpty == false {
                    DetailSection(title: "Episodes") {
                        LazyVStack(spacing: CinueSpacing.md) {
                            if let setShowWatchedAction, let setShowCollectedAction {
                                ShowBulkActionRow(
                                    markWatchedAction: {
                                        setShowWatchedAction(true)
                                    },
                                    markUnwatchedAction: {
                                        setShowWatchedAction(false)
                                    },
                                    collectAction: {
                                        setShowCollectedAction(true)
                                    },
                                    uncollectAction: {
                                        setShowCollectedAction(false)
                                    }
                                )
                            }

                            ForEach(snapshot.seasonGroups) { season in
                                SeasonDetailGroup(
                                    season: season,
                                    markWatchedAction: {
                                        setSeasonWatchedAction?(season, true)
                                    },
                                    markUnwatchedAction: {
                                        setSeasonWatchedAction?(season, false)
                                    },
                                    collectAction: {
                                        setSeasonCollectedAction?(season, true)
                                    },
                                    uncollectAction: {
                                        setSeasonCollectedAction?(season, false)
                                    },
                                    skipAction: {
                                        setSeasonSkippedAction?(season, true)
                                    },
                                    unskipAction: {
                                        setSeasonSkippedAction?(season, false)
                                    }
                                ) {
                                    ForEach(season.episodes) { episode in
                                        DetailEpisodeRow(
                                            episode: episode,
                                            showsWatchAction: episode.isWatched == false,
                                            markWatchedAction: {
                                                markEpisodeWatchedAction?(episode)
                                            },
                                            watchAgainAction: {
                                                watchEpisodeAgainAction?(episode)
                                            },
                                            markUnwatchedAction: {
                                                markEpisodeUnwatchedAction?(episode)
                                            },
                                            markWatchedUpToAction: {
                                                markEpisodeWatchedUpToAction?(episode)
                                            },
                                            toggleSkippedAction: {
                                                toggleEpisodeSkippedAction?(episode)
                                            },
                                            toggleCollectedAction: {
                                                toggleEpisodeCollectedAction?(episode)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

            }
            .padding(CinueSpacing.lg)
            .padding(.bottom, CinueSpacing.xxl * 2)
        }
        .cinueBottomChromeScrollMargins()
        .safeAreaPadding(.bottom, CinueSpacing.xxl * 2)
        .scrollIndicators(.hidden)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct MediaHero: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: MediaDetailSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: CinueSpacing.md) {
            CinuePosterImage(url: snapshot.item.posterURL, kind: snapshot.item.kind, width: 104, height: 156)

            VStack(alignment: .leading, spacing: CinueSpacing.sm) {
                Text(snapshot.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)

                Text(snapshot.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(3)

                HStack(spacing: CinueSpacing.sm) {
                    DetailStatusPill(text: snapshot.item.kindTitle)
                    DetailStatusPill(text: snapshot.item.statusLabel)

                    if let userRating = snapshot.userRating {
                        DetailStatusPill(text: "\(userRating)/10")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface(prominence: .elevated)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

}

private struct DetailStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, CinueSpacing.sm)
            .padding(.vertical, CinueSpacing.xs)
            .cinueGlassControl(cornerRadius: 14, tone: .primary, interactive: false, isSelected: false)
    }

    private var textColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }
}

private struct DetailActionGrid: View {
    let snapshot: MediaDetailSnapshot
    let markNextWatchedAction: (() -> Void)?
    let markMovieUnwatchedAction: (() -> Void)?
    let markMovieWatchedAction: (() -> Void)?
    let watchMovieAgainAction: (() -> Void)?
    let toggleMovieCollectedAction: (() -> Void)?
    let toggleFavoriteAction: () -> Void
    let toggleHiddenAction: () -> Void
    let manageListsAction: () -> Void
    let refreshMetadataAction: () -> Void
    let removeFromLibraryAction: () -> Void
    let editPersonalDetailsAction: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: CinueSpacing.sm) {
                actionGrid
            }
        } else {
            actionGrid
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CinueSpacing.sm) {
            actionButtons
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let markNextWatchedAction {
            DetailActionButton(title: "Mark Next", symbol: "checkmark.circle.fill", tone: .privacy, action: markNextWatchedAction)
        }

        if let markMovieWatchedAction, snapshot.item.watchCount == 0 {
            DetailActionButton(title: CinueCopy.State.markWatchedAction, symbol: "checkmark.circle.fill", tone: .privacy, action: markMovieWatchedAction)
        }

        if let watchMovieAgainAction, snapshot.item.watchCount > 0 {
            DetailActionButton(title: CinueCopy.State.watchAgainAction, symbol: "goforward.plus", tone: .privacy, action: watchMovieAgainAction)
        }

        if let markMovieUnwatchedAction {
            DetailActionButton(title: CinueCopy.State.markUnwatchedAction, symbol: "circle", tone: .neutral, action: markMovieUnwatchedAction)
        }

        if let toggleMovieCollectedAction {
            DetailActionButton(
                title: snapshot.item.isCollected ? CinueCopy.EpisodeDetail.removeFromCollectionAction : CinueCopy.EpisodeDetail.addToCollectionAction,
                symbol: snapshot.item.isCollected ? "bookmark.slash" : "bookmark",
                tone: .primary,
                action: toggleMovieCollectedAction
            )
        }

        DetailActionButton(
            title: favoriteTitle,
            symbol: snapshot.item.isFavorite ? "star.slash" : "star.fill",
            tone: .metadata,
            action: toggleFavoriteAction
        )

        DetailActionButton(
            title: snapshot.isHidden ? CinueCopy.State.showInLibraryAction : CinueCopy.State.hideFromLibraryAction,
            symbol: snapshot.isHidden ? "eye.fill" : "eye.slash.fill",
            tone: .neutral,
            action: toggleHiddenAction
        )

        DetailActionButton(
            title: "Manage Lists",
            symbol: "list.bullet",
            tone: .cloud,
            action: manageListsAction
        )

        DetailActionButton(
            title: "Refresh",
            symbol: "arrow.clockwise",
            tone: .metadata,
            action: refreshMetadataAction
        )

        DetailActionButton(
            title: "Edit Details",
            symbol: "pencil",
            tone: .primary,
            action: editPersonalDetailsAction
        )

        DetailActionButton(
            title: "Remove",
            symbol: "trash",
            tone: .neutral,
            action: removeFromLibraryAction
        )
    }

    private var favoriteTitle: String {
        if snapshot.item.kind == .movie {
            return snapshot.item.isFavorite ? CinueCopy.MovieDetail.removeFromWatchlistAction : CinueCopy.MovieDetail.addToWatchlistAction
        }

        return snapshot.item.isFavorite ? CinueCopy.State.removeFromFavoritesAction : CinueCopy.State.addToFavoritesAction
    }
}

private struct DetailActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let symbol: String
    let tone: CinueIconTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CinueSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tone.accent)
                    .frame(width: 28, height: 28)
                    .background(tone.accent.opacity(colorScheme == .dark ? 0.12 : 0.10), in: Circle())

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: CinueGlassMetrics.detailActionMinHeight, alignment: .leading)
            .padding(.horizontal, CinueSpacing.md)
            .cinueGlassControl(tone: tone, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.sm) {
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, CinueSpacing.xs)

            content()
        }
    }
}

private struct DetailTextSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let text: String

    var body: some View {
        DetailSection(title: title) {
            Text(text)
                .font(.body)
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CinueSpacing.md)
                .cinueContentSurface()
        }
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

}

private struct DetailPeopleSection: View {
    let title: String
    let credits: [MediaDetailCreditSnapshot]

    var body: some View {
        DetailSection(title: title) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: CinueSpacing.sm) {
                    ForEach(credits) { credit in
                        DetailPersonTile(credit: credit)
                    }
                }
                .padding(.horizontal, CinueSpacing.xs)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct DetailPersonTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let credit: MediaDetailCreditSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.xs) {
            CinueRemoteArtworkImage(
                url: credit.imageURL,
                pointSize: CGSize(width: 58, height: 58)
            ) { phase in
                switch phase {
                case let .success(image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        Circle()
                            .fill(CinueColors.accentBlue.opacity(colorScheme == .dark ? 0.18 : 0.12))

                        Image(systemName: "person.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(CinueColors.accentBlue)
                    }
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())

            Text(credit.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(2)
                .frame(width: 112, alignment: .leading)

            if let role = credit.role {
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)
                    .frame(width: 112, alignment: .leading)
            }
        }
        .padding(CinueSpacing.sm)
        .frame(width: 128, alignment: .leading)
        .cinueContentSurface(prominence: .quiet)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct DetailVideosSection: View {
    let videos: [MediaDetailVideoSnapshot]

    var body: some View {
        DetailSection(title: "Trailers") {
            VStack(spacing: CinueSpacing.sm) {
                ForEach(videos) { video in
                    Link(destination: video.url) {
                        DetailVideoRow(video: video)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DetailVideoRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let video: MediaDetailVideoSnapshot

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            Image(systemName: "play.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(CinueColors.accentBlue)

            VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)

                Text([video.type, video.site].joined(separator: " - "))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface(prominence: .quiet)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct DetailSimilarItemsSection: View {
    let items: [MediaDetailRelatedItemSnapshot]

    var body: some View {
        DetailSection(title: "More Like This") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: CinueSpacing.sm) {
                    ForEach(items) { item in
                        DetailSimilarItemTile(item: item)
                    }
                }
                .padding(.horizontal, CinueSpacing.xs)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct DetailSimilarItemTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: MediaDetailRelatedItemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.xs) {
            CinuePosterImage(url: item.posterURL, kind: item.kind, width: 92, height: 138)

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(2)

            if let releaseYear = item.releaseYear {
                Text(releaseYear)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .frame(width: 104, alignment: .leading)
        .padding(CinueSpacing.sm)
        .cinueContentSurface(prominence: .quiet)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct ShowBulkActionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let markWatchedAction: () -> Void
    let markUnwatchedAction: () -> Void
    let collectAction: () -> Void
    let uncollectAction: () -> Void

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            Text("Show Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Spacer(minLength: 0)

            Menu {
                Button("Mark Show Watched", systemImage: "checkmark.circle", action: markWatchedAction)
                Button("Mark Show Unwatched", systemImage: "circle", action: markUnwatchedAction)
                Button("Collect Show", systemImage: "bookmark", action: collectAction)
                Button("Uncollect Show", systemImage: "bookmark.slash", action: uncollectAction)
            } label: {
                Label("Bulk Actions", systemImage: "ellipsis.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .foregroundStyle(secondaryTextColor)
            .accessibilityLabel("Show bulk actions")
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface(prominence: .quiet)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct SeasonDetailGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let season: SeasonDetailSnapshot
    let markWatchedAction: () -> Void
    let markUnwatchedAction: () -> Void
    let collectAction: () -> Void
    let uncollectAction: () -> Void
    let skipAction: () -> Void
    let unskipAction: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CinueSpacing.sm) {
                VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                    Text(season.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)

                    Text(season.summary)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Mark Season Watched", systemImage: "checkmark.circle", action: markWatchedAction)
                    Button("Mark Season Unwatched", systemImage: "circle", action: markUnwatchedAction)
                    Button("Collect Season", systemImage: "bookmark", action: collectAction)
                    Button("Uncollect Season", systemImage: "bookmark.slash", action: uncollectAction)
                    Button("Skip Season", systemImage: "forward.circle", action: skipAction)
                    Button("Unskip Season", systemImage: "arrow.uturn.backward.circle", action: unskipAction)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                .accessibilityLabel("\(season.title) actions")
            }
            .padding(.horizontal, CinueSpacing.xs)

            content()
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct DetailEpisodeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CinuePreferenceKeys.hideEpisodeSpoilers) private var hideEpisodeSpoilers = false

    let episode: EpisodeDetailSnapshot
    let showsWatchAction: Bool
    let markWatchedAction: () -> Void
    let watchAgainAction: () -> Void
    let markUnwatchedAction: () -> Void
    let markWatchedUpToAction: () -> Void
    let toggleSkippedAction: () -> Void
    let toggleCollectedAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CinueSpacing.md) {
            NavigationLink(value: route) {
                VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                    Text(episode.displayTitleLine(hideSpoilers: hideEpisodeSpoilers))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)

                    HStack(spacing: CinueSpacing.xs) {
                        Text(episode.stateLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stateColor)

                        if let dateLine = episode.dateLine {
                            Text(dateLine)
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor.opacity(0.84))
                        }
                    }

                    if let overview = episode.displayOverview(hideSpoilers: hideEpisodeSpoilers) {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if showsWatchAction {
                Button(action: markWatchedAction) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(CinueColors.watchedGreen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(episode.titleLine) watched")
            }

            Menu {
                if episode.isWatched {
                    Button(CinueCopy.State.watchAgainAction, systemImage: "goforward.plus", action: watchAgainAction)
                    Button(CinueCopy.State.markUnwatchedAction, systemImage: "circle", action: markUnwatchedAction)
                } else {
                    Button(CinueCopy.State.markWatchedAction, systemImage: "checkmark.circle", action: markWatchedAction)
                }

                Button("Mark Watched Up To", systemImage: "checkmark.circle.trianglebadge.exclamationmark", action: markWatchedUpToAction)
                Button(episode.isSkipped ? CinueCopy.EpisodeDetail.unskipAction : CinueCopy.EpisodeDetail.skipAction, systemImage: episode.isSkipped ? "arrow.uturn.backward.circle" : "forward.circle", action: toggleSkippedAction)
                Button(episode.isCollected ? CinueCopy.EpisodeDetail.removeFromCollectionAction : CinueCopy.EpisodeDetail.addToCollectionAction, systemImage: episode.isCollected ? "bookmark.slash" : "bookmark", action: toggleCollectedAction)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .accessibilityLabel("Episode actions")
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface()
    }

    private var route: Route {
        .episodeDetail(showID: episode.showLocalID, season: episode.seasonNumber, episode: episode.episodeNumber ?? 0)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var stateColor: Color {
        switch episode.stateLabel {
        case CinueCopy.State.watched:
            return CinueColors.watchedGreen
        case CinueCopy.State.skipped:
            return CinueColors.reminderAmber
        case CinueCopy.State.inCollection:
            return CinueColors.accentBlue
        default:
            return secondaryTextColor
        }
    }
}

private struct EpisodeDetailContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(CinuePreferenceKeys.hideEpisodeSpoilers) private var hideEpisodeSpoilers = false

    let episode: EpisodeDetailSnapshot
    let actionMessage: String?
    let actionRoute: Route?
    let markWatchedAction: () -> Void
    let watchAgainAction: () -> Void
    let markUnwatchedAction: () -> Void
    let toggleSkippedAction: () -> Void
    let markWatchedUpToAction: () -> Void
    let toggleCollectedAction: () -> Void
    let editPersonalDetailsAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                Text(episode.showTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                DetailSection(title: CinueCopy.EpisodeDetail.sectionTitle) {
                    VStack(alignment: .leading, spacing: CinueSpacing.sm) {
                        Text(episode.displayTitleLine(hideSpoilers: hideEpisodeSpoilers))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)

                        Text(episode.stateReleaseLine)
                            .font(.subheadline)
                            .foregroundStyle(secondaryTextColor)

                        if let userRating = episode.userRating {
                            DetailStatusPill(text: "\(userRating)/10")
                        }

                        if episode.isWatched == false {
                            DetailActionButton(title: CinueCopy.State.markWatchedAction, symbol: "checkmark.circle.fill", tone: .privacy, action: markWatchedAction)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CinueSpacing.sm) {
                            if episode.isWatched {
                                DetailActionButton(title: CinueCopy.State.watchAgainAction, symbol: "goforward.plus", tone: .privacy, action: watchAgainAction)
                                DetailActionButton(title: CinueCopy.EpisodeDetail.unwatchAction, symbol: "circle", tone: .neutral, action: markUnwatchedAction)
                            }

                            DetailActionButton(title: "Watched Up To", symbol: "checkmark.circle.trianglebadge.exclamationmark", tone: .privacy, action: markWatchedUpToAction)
                            DetailActionButton(title: episode.isSkipped ? CinueCopy.EpisodeDetail.unskipAction : CinueCopy.EpisodeDetail.skipAction, symbol: episode.isSkipped ? "arrow.uturn.backward.circle" : "forward.circle", tone: .metadata, action: toggleSkippedAction)
                            DetailActionButton(title: episode.isCollected ? CinueCopy.EpisodeDetail.removeFromCollectionAction : CinueCopy.EpisodeDetail.addToCollectionAction, symbol: episode.isCollected ? "bookmark.slash" : "bookmark", tone: .primary, action: toggleCollectedAction)
                            DetailActionButton(title: "Edit Details", symbol: "pencil", tone: .primary, action: editPersonalDetailsAction)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CinueSpacing.md)
                    .cinueContentSurface(prominence: .elevated)
                }

                if let actionMessage {
                    DetailMessageRow(message: actionMessage, actionRoute: actionRoute)
                }

                if let notes = episode.notes {
                    DetailTextSection(title: CinueCopy.ShowDetail.notesTitle, text: notes)
                }

                if let overview = episode.displayOverview(hideSpoilers: hideEpisodeSpoilers) {
                    DetailTextSection(title: CinueCopy.EpisodeDetail.summaryTitle, text: overview)
                }
            }
            .padding(CinueSpacing.lg)
            .padding(.bottom, CinueSpacing.xxl * 2)
        }
        .cinueBottomChromeScrollMargins()
        .safeAreaPadding(.bottom, CinueSpacing.xxl * 2)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

}

private struct PersonalDetailsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (Int?, String?) -> Void

    @State private var rating: Int
    @State private var notesDraft: String

    init(
        title: String,
        userRating: Int?,
        notes: String?,
        onSave: @escaping (Int?, String?) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _rating = State(initialValue: userRating ?? 0)
        _notesDraft = State(initialValue: notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Text(title)
                        .font(.headline)
                        .lineLimit(3)
                }

                Section("Rating") {
                    Picker("Your Rating", selection: $rating) {
                        Text("No Rating").tag(0)
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)/10").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .accessibilityLabel("Your Rating")
                }

                Section("Private Notes") {
                    TextField("Private notes", text: $notesDraft, axis: .vertical)
                        .lineLimit(4...8)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Private notes")
                }
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(rating == 0 ? nil : rating, notesDraft)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DetailMessageRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: String
    let actionRoute: Route?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CinueSpacing.sm) {
                messageLine

                if let actionRoute {
                    Spacer(minLength: CinueSpacing.sm)
                    nextEpisodeLink(actionRoute)
                }
            }

            VStack(alignment: .leading, spacing: CinueSpacing.sm) {
                messageLine

                if let actionRoute {
                    nextEpisodeLink(actionRoute)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CinueSpacing.md)
        .cinueContentSurface(prominence: .quiet)
    }

    private var messageLine: some View {
        HStack(spacing: CinueSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CinueColors.watchedGreen)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func nextEpisodeLink(_ route: Route) -> some View {
        NavigationLink(value: route) {
            Label("View Next Episode", systemImage: "chevron.right.circle.fill")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(primaryTextColor)
                .padding(.horizontal, CinueSpacing.sm)
                .frame(minHeight: 34)
                .cinueGlassControl(cornerRadius: 17, tone: .primary, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View Next Episode")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

}

private func metadataRefreshStatusMessage(_ summary: MetadataRefreshSummary, title: String) -> String {
    if summary.refreshedItems > 0 {
        return "\(title) updated."
    }

    switch summary.failureReason {
    case .missingAPIKey:
        return "Add a TMDB key in Settings before refreshing \(title)."
    case .invalidCredential:
        return "The saved TMDB key was rejected."
    case .rateLimited:
        return "TMDB is rate limiting requests. Try again later."
    case .invalidResponse:
        return "TMDB returned unreadable data."
    case .providerUnavailable:
        return "TMDB is unavailable or the device is offline."
    case nil:
        return "Could not refresh \(title)."
    }
}

private struct CinueDetailMissingView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "exclamationmark.triangle", description: Text("The local item could not be found."))
    }
}

#Preview {
    let environment = AppEnvironment.preview()

    NavigationStack {
        ShowDetailView(localID: "preview")
            .environment(environment)
            .environment(\.managedObjectContext, environment.persistence.container.viewContext)
    }
}
