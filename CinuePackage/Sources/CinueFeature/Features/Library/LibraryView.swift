import CoreData
import SwiftUI

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var trackedItems: FetchedResults<NSManagedObject>
    @FetchRequest private var userLists: FetchedResults<NSManagedObject>
    @State private var selectedFilter: LibraryFilter = .all
    @State private var selectedSort: LibrarySort = .title
    @State private var actionMessage: String?
    @State private var itemForListManagement: LibraryItemSnapshot?
    @State private var itemPendingRemoval: LibraryItemSnapshot?

    init() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.sortDescriptors = [
            NSSortDescriptor(key: "kindRaw", ascending: false),
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        _trackedItems = FetchRequest(fetchRequest: request, animation: .default)

        let listRequest = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        listRequest.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        _userLists = FetchRequest(fetchRequest: listRequest, animation: .default)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            if trackedItems.isEmpty {
                emptyLibrary
            } else {
                libraryContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .cinueCinematicNavigationBar(colorScheme: colorScheme)
        .cinueAutoDismissFeedback($actionMessage)
        .sheet(item: $itemForListManagement) { item in
            ManageListsSheet(
                itemTitle: item.title,
                rows: listMembershipRows(for: item),
                toggleAction: { row in
                    setListMembership(row, for: item)
                }
            )
        }
        .alert("Remove from Library?", isPresented: removeAlertBinding) {
            Button("Cancel", role: .cancel) {
                itemPendingRemoval = nil
            }

            Button("Remove", role: .destructive) {
                removePendingItem()
            }
        } message: {
            Text("This removes local watch state, notes, and list membership for this item.")
        }
    }

    private var libraryContent: some View {
        let allSnapshots = librarySnapshots
        let visibleSnapshots = allSnapshots.filter { $0.isHidden == false }
        let snapshots = sortedSnapshots(filteredSnapshots(allSnapshots))
        let shows = snapshots.filter { $0.kind == .show }
        let movies = snapshots.filter { $0.kind == .movie }

        return VStack(spacing: 0) {
            CinueScreenHeader(title: "Library")
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                    LibrarySummaryRow(
                        totalCount: visibleSnapshots.count,
                        showCount: visibleSnapshots.filter { $0.kind == .show }.count,
                        movieCount: visibleSnapshots.filter { $0.kind == .movie }.count,
                        watchedCount: visibleSnapshots.filter { $0.watchCount > 0 }.count,
                        selectedFilter: selectedFilter,
                        selectionAction: { selectedFilter = $0 }
                    )

                    LibraryFilterPicker(
                        selectedFilter: $selectedFilter,
                        selectedSort: $selectedSort,
                        snapshots: allSnapshots
                    )

                    if let actionMessage {
                        LibraryActionMessageRow(message: actionMessage)
                    }

                    if shows.isEmpty == false {
                        LibrarySection(
                            title: "Shows",
                            items: shows,
                            markWatchedAction: { markWatched($0) },
                            toggleFavoriteAction: { toggleFavorite($0) },
                            hideAction: { hide($0) },
                            manageListsAction: { itemForListManagement = $0 },
                            refreshMetadataAction: { refreshMetadata($0) },
                            removeAction: { itemPendingRemoval = $0 }
                        )
                    }

                    if movies.isEmpty == false {
                        LibrarySection(
                            title: "Movies",
                            items: movies,
                            markWatchedAction: { markWatched($0) },
                            toggleFavoriteAction: { toggleFavorite($0) },
                            hideAction: { hide($0) },
                            manageListsAction: { itemForListManagement = $0 },
                            refreshMetadataAction: { refreshMetadata($0) },
                            removeAction: { itemPendingRemoval = $0 }
                        )
                    }

                    if snapshots.isEmpty {
                        LibraryEmptyFilterState(filter: selectedFilter)
                    }
                }
                .padding(.horizontal, CinueSpacing.lg)
                .padding(.top, CinueSpacing.lg)
                .padding(.bottom, CinueSpacing.xxl * 2)
            }
            .scrollIndicators(.hidden)
            .cinueBottomChromeScrollMargins()
        }
    }

    private var emptyLibrary: some View {
        CinuePlaceholderScreen(
            title: "Library",
            symbol: "rectangle.stack",
            headline: "Your Library Is Empty",
            message: CinueCopy.Library.emptyMessage,
            offersSampleLibrary: true
        )
    }

    private var librarySnapshots: [LibraryItemSnapshot] {
        LibraryItemSnapshotBuilder(context: viewContext)
            .snapshots(from: Array(trackedItems))
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private var removeAlertBinding: Binding<Bool> {
        Binding(
            get: { itemPendingRemoval != nil },
            set: { isPresented in
                if isPresented == false {
                    itemPendingRemoval = nil
                }
            }
        )
    }

    private func filteredSnapshots(_ snapshots: [LibraryItemSnapshot]) -> [LibraryItemSnapshot] {
        switch selectedFilter {
        case .all:
            return snapshots.filter { $0.isHidden == false }
        case .shows:
            return snapshots.filter { $0.kind == .show && $0.isHidden == false }
        case .movies:
            return snapshots.filter { $0.kind == .movie && $0.isHidden == false }
        case .favorites:
            return snapshots.filter { $0.isFavorite && $0.isHidden == false }
        case .watched:
            return snapshots.filter { ($0.watchCount > 0 || $0.statusLabel == CinueCopy.State.watched || $0.statusLabel == "Finished") && $0.isHidden == false }
        case .unwatched:
            return snapshots.filter { $0.watchCount == 0 && $0.statusLabel != "Finished" && $0.isHidden == false }
        case .hidden:
            return snapshots.filter(\.isHidden)
        }
    }

    private func sortedSnapshots(_ snapshots: [LibraryItemSnapshot]) -> [LibraryItemSnapshot] {
        switch selectedSort {
        case .title:
            return snapshots.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .status:
            return snapshots.sorted {
                if $0.statusLabel == $1.statusLabel {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }

                return $0.statusLabel.localizedCaseInsensitiveCompare($1.statusLabel) == .orderedAscending
            }
        case .recent:
            return snapshots.sorted {
                ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
            }
        }
    }

    private func markWatched(_ item: LibraryItemSnapshot) {
        do {
            if item.kind == .movie {
                try WatchStateStore(context: viewContext).markMovieWatched(localID: item.localID)
                actionMessage = "\(item.title) marked watched."
                return
            }

            guard let nextEpisode = MediaDetailSnapshotBuilder(context: viewContext)
                .snapshot(localID: item.localID, kind: .show)?
                .nextEpisode
            else {
                actionMessage = CinueCopy.Library.noReleasedNextEpisode(item.title)
                return
            }

            try WatchStateStore(context: viewContext).markEpisodeWatched(localID: nextEpisode.localID)
            actionMessage = "\(nextEpisode.titleLine) marked watched."
        } catch {
            actionMessage = "Could not update watch state."
        }
    }

    private func toggleFavorite(_ item: LibraryItemSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleFavorite(localID: item.localID, kind: item.kind)
            if item.kind == .movie {
                actionMessage = item.isFavorite ? CinueCopy.MovieDetail.removedFromWatchlist : CinueCopy.MovieDetail.addedToWatchlist
            } else {
                actionMessage = item.isFavorite ? CinueCopy.Library.removedFromFavorites : CinueCopy.Library.addedToFavorites
            }
        } catch {
            actionMessage = "Could not update favorite."
        }
    }

    private func hide(_ item: LibraryItemSnapshot) {
        do {
            try WatchStateStore(context: viewContext).toggleHidden(localID: item.localID, kind: item.kind)
            actionMessage = item.isHidden ? "Shown in Library." : CinueCopy.Library.hiddenFromLibrary
        } catch {
            actionMessage = "Could not update visibility."
        }
    }

    private func refreshMetadata(_ item: LibraryItemSnapshot) {
        actionMessage = "Refreshing \(item.title)."
        Task {
            let summary = await environment.metadataRefreshService.refreshMetadata(localID: item.localID, kind: item.kind)
            actionMessage = summary.refreshedItems > 0 ? "\(item.title) updated." : "Could not refresh \(item.title)."
        }
    }

    private func removePendingItem() {
        guard let item = itemPendingRemoval else {
            return
        }

        do {
            try ContentLibraryStore(context: viewContext).removeFromLibrary(localID: item.localID, kind: item.kind)
            actionMessage = "\(item.title) removed from Library."
        } catch {
            actionMessage = "Could not remove item."
        }

        itemPendingRemoval = nil
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

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case shows
    case movies
    case favorites
    case watched
    case unwatched
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .shows:
            return "Shows"
        case .movies:
            return "Movies"
        case .favorites:
            return "Favorites"
        case .watched:
            return "Watched"
        case .unwatched:
            return "Unwatched"
        case .hidden:
            return "Hidden"
        }
    }

    func count(in snapshots: [LibraryItemSnapshot]) -> Int {
        switch self {
        case .all:
            return snapshots.filter { $0.isHidden == false }.count
        case .shows:
            return snapshots.filter { $0.kind == .show && $0.isHidden == false }.count
        case .movies:
            return snapshots.filter { $0.kind == .movie && $0.isHidden == false }.count
        case .favorites:
            return snapshots.filter { $0.isFavorite && $0.isHidden == false }.count
        case .watched:
            return snapshots.filter { ($0.watchCount > 0 || $0.statusLabel == CinueCopy.State.watched || $0.statusLabel == "Finished") && $0.isHidden == false }.count
        case .unwatched:
            return snapshots.filter { $0.watchCount == 0 && $0.statusLabel != "Finished" && $0.isHidden == false }.count
        case .hidden:
            return snapshots.filter(\.isHidden).count
        }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case title
    case status
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .status:
            return "Status"
        case .recent:
            return "Release"
        }
    }

    var symbol: String {
        switch self {
        case .title:
            return "textformat"
        case .status:
            return "checkmark.circle"
        case .recent:
            return "calendar"
        }
    }
}

private struct LibrarySummaryRow: View {
    let totalCount: Int
    let showCount: Int
    let movieCount: Int
    let watchedCount: Int
    let selectedFilter: LibraryFilter
    let selectionAction: (LibraryFilter) -> Void

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            summaryButton(filter: .all, title: "All", value: totalCount, symbol: "rectangle.stack.fill", tone: .primary)
            summaryButton(filter: .shows, title: "Shows", value: showCount, symbol: "tv.fill", tone: .metadata)
            summaryButton(filter: .movies, title: "Movies", value: movieCount, symbol: "film.fill", tone: .importExport)
            summaryButton(filter: .watched, title: "Watched", value: watchedCount, symbol: "checkmark.circle.fill", tone: .privacy)
        }
    }

    private func summaryButton(filter: LibraryFilter, title: String, value: Int, symbol: String, tone: CinueIconTone) -> some View {
        Button {
            selectionAction(filter)
        } label: {
            LibrarySummaryTile(
                title: title,
                value: value,
                symbol: symbol,
                tone: tone,
                isSelected: selectedFilter == filter
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct LibrarySummaryTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: Int
    let symbol: String
    let tone: CinueIconTone
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.xs) {
            CinueIconTile(symbol: symbol, tone: tone, size: 30)

            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CinueSpacing.sm)
        .cinueCompactGlassControl(cornerRadius: CinueRadius.md, tone: tone, isSelected: isSelected)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var tileBackground: Color {
        if isSelected {
            return CinueColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.14)
        }

        return colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.86)
    }

    private var tileBorder: Color {
        if isSelected {
            return CinueColors.accentBlue.opacity(0.48)
        }

        return colorScheme == .dark ? .white.opacity(0.08) : tone.accent.opacity(0.12)
    }
}

private struct LibraryFilterPicker: View {
    @Binding var selectedFilter: LibraryFilter
    @Binding var selectedSort: LibrarySort
    let snapshots: [LibraryItemSnapshot]

    var body: some View {
        ScrollView(.horizontal) {
            filterRow
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
    }

    private var filterRow: some View {
        HStack(spacing: CinueSpacing.sm) {
            Menu {
                Picker("Sort", selection: $selectedSort) {
                    ForEach(LibrarySort.allCases) { sort in
                        Label(sort.title, systemImage: sort.symbol)
                            .tag(sort)
                    }
                }
            } label: {
                LibrarySortButton()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort by \(selectedSort.title)")

            ForEach(LibraryFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    LibraryFilterPill(
                        title: filter.title,
                        count: filter.count(in: snapshots),
                        isSelected: filter == selectedFilter
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.title), \(filter.count(in: snapshots))")
            }
        }
        .padding(.horizontal, CinueSpacing.xs)
        .padding(.vertical, CinueSpacing.xs)
    }
}

private struct LibrarySortButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(textColor)
            .frame(width: 42, height: 42)
            .cinueCompactGlassControl(cornerRadius: 21, tone: .neutral)
    }

    private var textColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }
}

private struct LibraryFilterPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: CinueSpacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            CinuePillCountBadge(count: count, isSelected: isSelected)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, CinueSpacing.md)
        .frame(minHeight: 42)
        .cinueCompactGlassControl(cornerRadius: 21, tone: .primary, isSelected: isSelected)
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
        }

        return colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextPrimary
    }
}

private struct LibraryActionMessageRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: String

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CinueColors.watchedGreen)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CinueSpacing.md)
        .cinueContentSurface(prominence: .quiet)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.58) : .white.opacity(0.72)
    }
}

struct ListMembershipRowSnapshot: Identifiable, Equatable {
    var id: String { localID }
    let localID: String
    let name: String
    var isIncluded: Bool
}

@MainActor
struct ListMembershipRowBuilder {
    let context: NSManagedObjectContext

    func rows(for item: LibraryItemSnapshot, lists rawLists: [NSManagedObject]) -> [ListMembershipRowSnapshot] {
        let lists = rawLists.map { list in
            (
                localID: list.value(forKey: "localID") as? String ?? "",
                name: list.value(forKey: "name") as? String ?? "Untitled List"
            )
        }
        .filter { $0.localID.isEmpty == false }

        guard lists.isEmpty == false else {
            return []
        }

        let listIDs = lists.map(\.localID)
        let membershipRequest = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        membershipRequest.predicate = listMembershipPredicate(item: item, listIDs: listIDs)
        let memberships = (try? context.fetch(membershipRequest)) ?? []
        let includedListIDs = Set(memberships.compactMap { $0.value(forKey: "listLocalID") as? String })

        return lists.map { list in
            ListMembershipRowSnapshot(
                localID: list.localID,
                name: list.name,
                isIncluded: includedListIDs.contains(list.localID)
            )
        }
    }

    private func listMembershipPredicate(item: LibraryItemSnapshot, listIDs: [String]) -> NSPredicate {
        var itemPredicates = [
            NSPredicate(format: "itemLocalID == %@", item.localID)
        ]
        if let tvdbID = item.tvdbID {
            itemPredicates.append(NSPredicate(format: "tvdbID == %@", NSNumber(value: tvdbID)))
        }
        if let tmdbID = item.tmdbID {
            itemPredicates.append(NSPredicate(format: "tmdbID == %@", NSNumber(value: tmdbID)))
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "listLocalID IN %@", listIDs),
            NSCompoundPredicate(orPredicateWithSubpredicates: itemPredicates)
        ])
    }
}

struct ManageListsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let itemTitle: String
    let toggleAction: (ListMembershipRowSnapshot) -> Void
    @State private var rows: [ListMembershipRowSnapshot]

    init(
        itemTitle: String,
        rows: [ListMembershipRowSnapshot],
        toggleAction: @escaping (ListMembershipRowSnapshot) -> Void
    ) {
        self.itemTitle = itemTitle
        self.toggleAction = toggleAction
        _rows = State(initialValue: rows)
    }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "No Lists",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a list first, then add this item.")
                    )
                } else {
                    Section(itemTitle) {
                        ForEach(rows) { row in
                            Button {
                                toggleAction(row)
                                if let index = rows.firstIndex(where: { $0.localID == row.localID }) {
                                    rows[index].isIncluded.toggle()
                                }
                            } label: {
                                HStack {
                                    Text(row.name)
                                    Spacer()
                                    if row.isIncluded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(CinueColors.watchedGreen)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Manage Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LibraryEmptyFilterState: View {
    @Environment(\.colorScheme) private var colorScheme

    let filter: LibraryFilter

    var body: some View {
        VStack(spacing: CinueSpacing.xs) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CinueColors.accentBlue)

            Text("No \(filter.title)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Text("Try another filter.")
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(CinueSpacing.lg)
        .cinueContentSurface()
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.88)
    }
}

private struct LibrarySection: View {
    let title: String
    let items: [LibraryItemSnapshot]
    let markWatchedAction: (LibraryItemSnapshot) -> Void
    let toggleFavoriteAction: (LibraryItemSnapshot) -> Void
    let hideAction: (LibraryItemSnapshot) -> Void
    let manageListsAction: (LibraryItemSnapshot) -> Void
    let refreshMetadataAction: (LibraryItemSnapshot) -> Void
    let removeAction: (LibraryItemSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.sm) {
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, CinueSpacing.xs)

            LazyVStack(spacing: CinueSpacing.sm) {
                ForEach(items) { item in
                    LibraryItemRow(
                        item: item,
                        markWatchedAction: {
                            markWatchedAction(item)
                        },
                        toggleFavoriteAction: {
                            toggleFavoriteAction(item)
                        },
                        hideAction: {
                            hideAction(item)
                        },
                        manageListsAction: {
                            manageListsAction(item)
                        },
                        refreshMetadataAction: {
                            refreshMetadataAction(item)
                        },
                        removeAction: {
                            removeAction(item)
                        }
                    )
                }
            }
        }
    }
}

struct LibraryItemRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: LibraryItemSnapshot
    var markWatchedAction: (() -> Void)?
    var toggleFavoriteAction: (() -> Void)?
    var hideAction: (() -> Void)?
    var manageListsAction: (() -> Void)?
    var refreshMetadataAction: (() -> Void)?
    var removeAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: CinueSpacing.md) {
            NavigationLink(value: route) {
                rowContent
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if shouldShowWatchButton, let markWatchedAction {
                Button(action: markWatchedAction) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(CinueColors.watchedGreen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark watched")
            }

            if toggleFavoriteAction != nil || hideAction != nil || markWatchedAction != nil || manageListsAction != nil || refreshMetadataAction != nil || removeAction != nil {
                Menu {
                    if let markWatchedAction {
                        Button(item.kind == .movie ? "Mark Watched" : "Mark Next Watched", systemImage: "checkmark.circle", action: markWatchedAction)
                    }

                    if let toggleFavoriteAction {
                        Button(favoriteActionTitle, systemImage: item.isFavorite ? "star.slash" : "star", action: toggleFavoriteAction)
                    }

                    if let hideAction {
                        if item.isHidden {
                            Button(CinueCopy.State.showInLibraryAction, systemImage: "eye", action: hideAction)
                        } else {
                            Button(CinueCopy.State.hideFromLibraryAction, systemImage: "eye.slash", role: .destructive, action: hideAction)
                        }
                    }

                    if let manageListsAction {
                        Button("Manage Lists", systemImage: "list.bullet", action: manageListsAction)
                    }

                    if let refreshMetadataAction {
                        Button("Refresh Metadata", systemImage: "arrow.clockwise", action: refreshMetadataAction)
                    }

                    if let removeAction {
                        Button("Remove from Library", systemImage: "trash", role: .destructive, action: removeAction)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                .accessibilityLabel("More actions")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor.opacity(0.65))
            }
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface()
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: CinueSpacing.md) {
            CinuePosterImage(url: item.posterURL, kind: item.kind, width: 58, height: 86)

            VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: CinueSpacing.xs) {
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CinueColors.reminderAmber)
                            .accessibilityLabel("Favorite")
                    }
                }

                HStack(spacing: CinueSpacing.xs) {
                    Text(item.statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)

                    Text(item.kindTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryTextColor)

                    if let providerStatusLabel = item.providerStatusLabel {
                        Text(providerStatusLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(providerStatusColor)
                    }
                }

                Text(item.detailLine)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)

                if let secondaryLine = item.secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.88)
    }

    private var rowBorder: Color {
        colorScheme == .dark ? .white.opacity(0.08) : CinueColors.accentBlue.opacity(0.10)
    }

    private var statusColor: Color {
        switch item.statusLabel {
        case CinueCopy.State.watched, "Finished":
            CinueColors.watchedGreen
        case "Watching":
            CinueColors.accentBlue
        default:
            secondaryTextColor
        }
    }

    private var providerStatusColor: Color {
        switch item.providerStatusLabel {
        case "Continuing":
            CinueColors.accentBlue
        case "Ended", "Cancelled":
            secondaryTextColor
        default:
            CinueColors.reminderAmber
        }
    }

    private var route: Route {
        item.kind == .movie ? .movieDetail(item.localID) : .showDetail(item.localID)
    }

    private var favoriteActionTitle: String {
        if item.kind == .movie {
            return item.isFavorite ? CinueCopy.MovieDetail.removeFromWatchlistAction : CinueCopy.MovieDetail.addToWatchlistAction
        }

        return item.isFavorite ? CinueCopy.State.removeFromFavoritesAction : CinueCopy.State.addToFavoritesAction
    }

    private var shouldShowWatchButton: Bool {
        item.watchCount == 0 || item.statusLabel == "Watching"
    }
}

#Preview {
    let environment = AppEnvironment.preview()

    NavigationStack {
        LibraryView()
            .environment(environment)
            .environment(\.managedObjectContext, environment.persistence.container.viewContext)
    }
}
