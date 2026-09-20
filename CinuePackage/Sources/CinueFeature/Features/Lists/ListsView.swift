import CoreData
import SwiftUI

enum CinueListsLayoutMetrics {
    static let usesSiblingHeaderAndScrollableBody = true
    static let usesSummaryTileRow = true
    static let createActionIsInlineCommand = false
    static let summaryTileCount = 4
    static let metricIconSize: CGFloat = 30
}

struct ListsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var userLists: FetchedResults<NSManagedObject>
    @State private var selectedListID: String?
    @State private var actionMessage: String?
    @State private var draftListName = ""
    @State private var isAddingList = false
    @State private var isRenamingList = false
    @State private var listForRename: UserListSnapshot?
    @State private var listForDelete: UserListSnapshot?
    @State private var itemForListManagement: LibraryItemSnapshot?

    init() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        _userLists = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            if userLists.isEmpty {
                emptyLists
            } else {
                listsContent
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
        .alert("New List", isPresented: $isAddingList) {
            TextField("List name", text: $draftListName)

            Button("Cancel", role: .cancel) {
                draftListName = ""
            }

            Button("Create") {
                createList()
            }
        }
        .alert("Rename List", isPresented: $isRenamingList) {
            TextField("List name", text: $draftListName)

            Button("Cancel", role: .cancel) {
                draftListName = ""
            }

            Button("Rename") {
                renameList()
            }
        }
        .alert("Delete List?", isPresented: deleteBinding) {
            Button("Cancel", role: .cancel) {
                listForDelete = nil
            }

            Button("Delete", role: .destructive) {
                deleteSelectedList()
            }
        } message: {
            Text("The list will be deleted. Items stay in Library.")
        }
    }

    private var listsContent: some View {
        let snapshots = listSnapshots
        let selected = selectedSnapshot(from: snapshots)

        return VStack(spacing: 0) {
            CinueScreenHeader(title: "Lists")
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                    ListsSummaryRow(
                        listCount: snapshots.count,
                        itemCount: snapshots.reduce(0) { $0 + $1.itemCount },
                        availableCount: snapshots.reduce(0) { $0 + $1.resolvedItemCount },
                        createAction: showCreateListAlert
                    )

                    if let actionMessage {
                        ListActionMessageRow(message: actionMessage)
                    }

                    ListSelector(
                        lists: snapshots,
                        selectedListID: selected?.localID,
                        selectionAction: { selectedListID = $0.localID }
                    )

                    if let selected {
                        ListDetailCard(
                            list: selected,
                            renameAction: {
                                draftListName = selected.name
                                listForRename = selected
                                isRenamingList = true
                            },
                            deleteAction: {
                                listForDelete = selected
                            },
                            moveListEarlierAction: {
                                moveList(selected, direction: .earlier)
                            },
                            moveListLaterAction: {
                                moveList(selected, direction: .later)
                            },
                            sortItemsAction: { mode in
                                sortItems(in: selected, mode: mode)
                            },
                            removeItemAction: { listItem in
                                removeListItem(listItem)
                            },
                            moveItemAction: { listItem, direction in
                                moveListItem(listItem, direction: direction)
                            },
                            markWatchedAction: { item in
                                markWatched(item)
                            },
                            toggleFavoriteAction: { item in
                                toggleFavorite(item)
                            },
                            manageListsAction: { item in
                                itemForListManagement = item
                            }
                        )
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

    private var emptyLists: some View {
        CinuePlaceholderScreen(
            title: "Lists",
            symbol: "list.bullet.rectangle",
            headline: "No Lists Yet",
            message: CinueCopy.Lists.emptyMessage
        )
    }

    private var listSnapshots: [UserListSnapshot] {
        UserListSnapshotBuilder(context: viewContext)
            .snapshots(from: Array(userLists))
    }

    private func selectedSnapshot(from snapshots: [UserListSnapshot]) -> UserListSnapshot? {
        if let selectedListID,
           let selected = snapshots.first(where: { $0.localID == selectedListID }) {
            return selected
        }

        return snapshots.first
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { listForDelete != nil },
            set: { isPresented in
                if isPresented == false {
                    listForDelete = nil
                }
            }
        )
    }

    private func showCreateListAlert() {
        draftListName = ""
        isAddingList = true
    }

    private func createList() {
        do {
            let localID = try ContentLibraryStore(context: viewContext).createUserList(name: draftListName)
            selectedListID = localID
            actionMessage = "List created."
            draftListName = ""
        } catch {
            actionMessage = "Enter a list name."
        }
    }

    private func renameList() {
        guard let listForRename else {
            return
        }

        do {
            try ContentLibraryStore(context: viewContext).renameUserList(localID: listForRename.localID, name: draftListName)
            selectedListID = listForRename.localID
            actionMessage = "List renamed."
            draftListName = ""
            self.listForRename = nil
        } catch {
            actionMessage = "Enter a list name."
        }
    }

    private func deleteSelectedList() {
        guard let listForDelete else {
            return
        }

        do {
            try ContentLibraryStore(context: viewContext).deleteUserList(localID: listForDelete.localID)
            selectedListID = nil
            actionMessage = "List deleted. Library items were kept."
        } catch {
            actionMessage = "Could not delete list."
        }

        self.listForDelete = nil
    }

    private func moveList(_ list: UserListSnapshot, direction: ListMoveDirection) {
        do {
            try ContentLibraryStore(context: viewContext).moveUserList(localID: list.localID, direction: direction)
            selectedListID = list.localID
            actionMessage = direction == .earlier ? "List moved earlier." : "List moved later."
        } catch {
            actionMessage = "Could not reorder list."
        }
    }

    private func sortItems(in list: UserListSnapshot, mode: ListItemSortMode) {
        do {
            try ContentLibraryStore(context: viewContext).sortListItems(listLocalID: list.localID, mode: mode)
            selectedListID = list.localID
            actionMessage = sortMessage(for: mode)
        } catch {
            actionMessage = "Could not sort list."
        }
    }

    private func removeListItem(_ listItem: UserListItemSnapshot) {
        do {
            try ContentLibraryStore(context: viewContext).removeListItem(localID: listItem.listItemLocalID)
            actionMessage = "\(listItem.item.title) removed from list."
        } catch {
            actionMessage = "Could not remove item."
        }
    }

    private func moveListItem(_ listItem: UserListItemSnapshot, direction: ListMoveDirection) {
        do {
            try ContentLibraryStore(context: viewContext).moveListItem(localID: listItem.listItemLocalID, direction: direction)
            actionMessage = direction == .earlier ? "\(listItem.item.title) moved up." : "\(listItem.item.title) moved down."
        } catch {
            actionMessage = "Could not reorder item."
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

    private func sortMessage(for mode: ListItemSortMode) -> String {
        switch mode {
        case .titleAscending:
            return "List sorted A to Z."
        case .titleDescending:
            return "List sorted Z to A."
        case .titleAscendingIgnoringArticles:
            return "List sorted by title without articles."
        case .mediaKindThenTitle:
            return "List sorted by type."
        case .latestEpisode:
            return "List sorted by latest episode."
        case .oldestEpisode:
            return "List sorted by oldest episode."
        case .lastWatched:
            return "List sorted by last watched."
        case .leastRemainingEpisodes:
            return "List sorted by least remaining."
        }
    }
}

private struct ListsSummaryRow: View {
    let listCount: Int
    let itemCount: Int
    let availableCount: Int
    let createAction: () -> Void

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            ListSummaryTile(title: "Lists", value: listCount, symbol: "list.bullet.rectangle.fill", tone: .cloud)
            ListSummaryTile(title: "Items", value: itemCount, symbol: "rectangle.stack.fill", tone: .primary)
            ListSummaryTile(title: "Ready", value: availableCount, symbol: "checkmark.circle.fill", tone: .privacy)

            Button(action: createAction) {
                ListSummaryTile(title: "List", value: nil, symbol: "plus", tone: .primary, interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create list")
        }
    }
}

private struct ListSummaryTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: Int?
    let symbol: String
    let tone: CinueIconTone
    var interactive = false

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.xs) {
            CinueIconTile(symbol: symbol, tone: tone, size: CinueListsLayoutMetrics.metricIconSize)

            Text(valueText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CinueSpacing.sm)
        .cinueCompactGlassControl(cornerRadius: CinueRadius.md, tone: tone, isSelected: interactive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var valueText: String {
        if let value {
            return "\(value)"
        }

        return "New"
    }

    private var accessibilityLabel: String {
        if let value {
            return "\(value) \(title)"
        }

        return "New \(title)"
    }
}

private struct ListSelector: View {
    let lists: [UserListSnapshot]
    let selectedListID: String?
    let selectionAction: (UserListSnapshot) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            selectorRow
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
    }

    private var selectorRow: some View {
        HStack(spacing: CinueSpacing.sm) {
            ForEach(lists) { list in
                Button {
                    selectionAction(list)
                } label: {
                    ListSelectorPill(
                        title: list.name,
                        count: list.itemCount,
                        isSelected: list.localID == selectedListID
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(list.name), \(list.subtitle)")
            }
        }
        .padding(.horizontal, CinueSpacing.xs)
        .padding(.vertical, CinueSpacing.xs)
    }
}

private struct ListActionMessageRow: View {
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

private struct ListSelectorPill: View {
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

private struct ListDetailCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let list: UserListSnapshot
    let renameAction: () -> Void
    let deleteAction: () -> Void
    let moveListEarlierAction: () -> Void
    let moveListLaterAction: () -> Void
    let sortItemsAction: (ListItemSortMode) -> Void
    let removeItemAction: (UserListItemSnapshot) -> Void
    let moveItemAction: (UserListItemSnapshot, ListMoveDirection) -> Void
    let markWatchedAction: (LibraryItemSnapshot) -> Void
    let toggleFavoriteAction: (LibraryItemSnapshot) -> Void
    let manageListsAction: (LibraryItemSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: CinueSpacing.sm) {
                VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                    Text(list.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)

                    Text(list.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer(minLength: 0)

                Menu {
                    Section("List") {
                        Button("Rename", systemImage: "pencil", action: renameAction)
                        Button("Move Earlier", systemImage: "arrow.up", action: moveListEarlierAction)
                        Button("Move Later", systemImage: "arrow.down", action: moveListLaterAction)
                    }

                    Section("Sort Items") {
                        Button("Title A to Z", systemImage: "textformat.abc", action: {
                            sortItemsAction(.titleAscending)
                        })
                        Button("Title Z to A", systemImage: "textformat.abc.dottedunderline", action: {
                            sortItemsAction(.titleDescending)
                        })
                        Button("Title, Ignore Articles", systemImage: "textformat.abc", action: {
                            sortItemsAction(.titleAscendingIgnoringArticles)
                        })
                        Button("Type, Then Title", systemImage: "square.stack.3d.up", action: {
                            sortItemsAction(.mediaKindThenTitle)
                        })
                        Button("Latest Episode", systemImage: "calendar.badge.clock", action: {
                            sortItemsAction(.latestEpisode)
                        })
                        Button("Oldest Episode", systemImage: "calendar", action: {
                            sortItemsAction(.oldestEpisode)
                        })
                        Button("Last Watched", systemImage: "clock.arrow.circlepath", action: {
                            sortItemsAction(.lastWatched)
                        })
                        Button("Least Remaining", systemImage: "checklist", action: {
                            sortItemsAction(.leastRemainingEpisodes)
                        })
                    }

                    Button("Delete", systemImage: "trash", role: .destructive, action: deleteAction)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                .accessibilityLabel("Manage list")
            }

            if list.items.isEmpty {
                ListEmptyState(list: list)
            } else {
                LazyVStack(spacing: CinueSpacing.sm) {
                    ForEach(list.listItems) { listItem in
                        ManagedListItemRow(
                            listItem: listItem,
                            removeAction: {
                                removeItemAction(listItem)
                            },
                            moveEarlierAction: {
                                moveItemAction(listItem, .earlier)
                            },
                            moveLaterAction: {
                                moveItemAction(listItem, .later)
                            },
                            markWatchedAction: {
                                markWatchedAction(listItem.item)
                            },
                            toggleFavoriteAction: {
                                toggleFavoriteAction(listItem.item)
                            },
                            manageListsAction: {
                                manageListsAction(listItem.item)
                            }
                        )
                    }
                }

                if list.unresolvedItemCount > 0 {
                    UnresolvedListItemsRow(count: list.unresolvedItemCount)
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
}

private struct ManagedListItemRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let listItem: UserListItemSnapshot
    let removeAction: () -> Void
    let moveEarlierAction: () -> Void
    let moveLaterAction: () -> Void
    let markWatchedAction: () -> Void
    let toggleFavoriteAction: () -> Void
    let manageListsAction: () -> Void

    private var item: LibraryItemSnapshot {
        listItem.item
    }

    var body: some View {
        HStack(alignment: .center, spacing: CinueSpacing.md) {
            NavigationLink(value: route) {
                HStack(alignment: .top, spacing: CinueSpacing.md) {
                    CinuePosterImage(url: item.posterURL, kind: item.kind, width: 58, height: 86)

                    VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                        Text(item.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(2)

                        Text(item.statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)

                        Text(item.detailLine)
                            .font(.subheadline)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Menu {
                Button(item.kind == .movie ? "Mark Watched" : "Mark Next Watched", systemImage: "checkmark.circle", action: markWatchedAction)
                Button(favoriteActionTitle, systemImage: item.isFavorite ? "star.slash" : "star", action: toggleFavoriteAction)
                Button("Manage Lists", systemImage: "list.bullet", action: manageListsAction)
                Section("Order") {
                    Button("Move Up", systemImage: "arrow.up", action: moveEarlierAction)
                    Button("Move Down", systemImage: "arrow.down", action: moveLaterAction)
                }
                Button("Remove from List", systemImage: "minus.circle", role: .destructive, action: removeAction)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .accessibilityLabel("More actions")
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface()
    }

    private var route: Route {
        item.kind == .movie ? .movieDetail(item.localID) : .showDetail(item.localID)
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

    private var favoriteActionTitle: String {
        if item.kind == .movie {
            return item.isFavorite ? CinueCopy.MovieDetail.removeFromWatchlistAction : CinueCopy.MovieDetail.addToWatchlistAction
        }

        return item.isFavorite ? CinueCopy.State.removeFromFavoritesAction : CinueCopy.State.addToFavoritesAction
    }
}

private struct ListEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    let list: UserListSnapshot

    var body: some View {
        VStack(spacing: CinueSpacing.xs) {
            Image(systemName: list.unresolvedItemCount > 0 ? "tray.and.arrow.down.fill" : "list.bullet.rectangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CinueColors.accentBlue)

            Text(list.unresolvedItemCount > 0 ? "Items Need Library Matches" : "This List Is Empty")
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Text(list.unresolvedItemCount > 0 ? CinueCopy.Lists.unresolvedItemMessage : CinueCopy.Lists.emptyListMessage)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
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

    private var rowBorder: Color {
        colorScheme == .dark ? .white.opacity(0.08) : CinueColors.accentBlue.opacity(0.10)
    }
}

private struct UnresolvedListItemsRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let count: Int

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CinueColors.reminderAmber)

            Text(count == 1 ? "1 item needs a Library match." : "\(count) items need Library matches.")
                .font(.subheadline)
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

#Preview {
    let environment = AppEnvironment.preview()

    NavigationStack {
        ListsView()
            .environment(environment)
            .environment(\.managedObjectContext, environment.persistence.container.viewContext)
    }
}
