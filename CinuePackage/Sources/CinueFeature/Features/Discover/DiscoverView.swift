import CoreData
import SwiftUI

struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @FetchRequest private var trackedItems: FetchedResults<NSManagedObject>
    @State private var model: DiscoverModel?
    @State private var selectedResult: MediaSummary?
    @State private var actionMessage: String?
    @FocusState private var isSearchFocused: Bool

    init() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        _trackedItems = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            if let model {
                content(model)
            } else {
                ProgressView()
                    .tint(CinueColors.accentBlue)
            }
        }
        .task {
            if model == nil {
                model = DiscoverModel(provider: environment.tmdbClient)
            }
        }
        .sheet(item: $selectedResult) { item in
            DiscoverItemPreviewSheet(
                item: item,
                isTracked: isTracked(item),
                isInWatchlist: isInWatchlist(item),
                actionMessage: actionMessage,
                addToLibrary: {
                    addToLibrary(item)
                },
                addToWatchlist: {
                    addToWatchlist(item)
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .cinueCinematicNavigationBar(colorScheme: colorScheme)
        .cinueAutoDismissFeedback($actionMessage)
    }

    private func content(_ model: DiscoverModel) -> some View {
        VStack(spacing: 0) {
            CinueScreenHeader(title: "Discover")
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: CinueSpacing.md) {
                searchField(model)

                DiscoverCategoryRow(
                    selectedCategory: model.selectedCategory,
                    isLoading: model.isSearching,
                    browseAction: { category in
                        Task { await model.browse(category) }
                    }
                )

                if let message = model.errorMessage {
                    DiscoverMessageRow(message: message, symbol: "key.fill", tone: .metadata)
                }

                if let actionMessage {
                    DiscoverMessageRow(message: actionMessage, symbol: "checkmark.circle.fill", tone: .privacy)
                }

                if model.results.isEmpty {
                    emptyState(model)
                } else {
                    if let selectedCategory = model.selectedCategory {
                        Text(selectedCategory.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    resultList(model.results)
                }
            }
            .padding(.horizontal, CinueSpacing.lg)
            .padding(.top, CinueSpacing.lg)
            .padding(.bottom, CinueSpacing.xxl)
        }
        .overlay {
            if model.isSearching {
                ProgressView("Searching")
                    .padding(CinueSpacing.lg)
                    .cinueGlass(cornerRadius: CinueRadius.lg)
            }
        }
    }

    private func searchField(_ model: DiscoverModel) -> some View {
        VStack(spacing: CinueSpacing.sm) {
            HStack(spacing: CinueSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CinueColors.accentBlue)

                TextField("Search movies and shows", text: Binding(
                    get: { model.query },
                    set: { model.query = $0 }
                ))
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit {
                    Task { await model.search() }
                }

                if model.query.isEmpty == false {
                    Button {
                        model.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    isSearchFocused = true
                }
            )
            .padding(.horizontal, CinueSpacing.md)
            .frame(minHeight: 48)
            .cinueGlassControl(cornerRadius: CinueRadius.lg, tone: .primary, interactive: true)
        }
    }

    private func emptyState(_ model: DiscoverModel) -> some View {
        VStack(spacing: CinueSpacing.lg) {
            CinueBrandMark(size: 64, symbol: "magnifyingglass")

            VStack(spacing: CinueSpacing.xs) {
                Text(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CinueCopy.Discover.emptyTitle : CinueCopy.Discover.noResultsTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Text(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CinueCopy.Discover.emptyMessage : CinueCopy.Discover.noResultsMessage)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, CinueSpacing.xxl)
    }

    private func resultList(_ results: [MediaSummary]) -> some View {
        List(results) { item in
            DiscoverResultRow(
                item: item,
                isTracked: isTracked(item),
                addAction: {
                    addToLibrary(item)
                },
                previewAction: {
                    actionMessage = nil
                    selectedResult = item
                }
            )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .cinueBottomChromeScrollMargins()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var searchFieldBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated : .white
    }

    private var searchFieldBorder: Color {
        colorScheme == .dark ? .white.opacity(0.10) : CinueColors.accentBlue.opacity(0.16)
    }

    private func isTracked(_ item: MediaSummary) -> Bool {
        trackedItem(for: item) != nil
    }

    private func isInWatchlist(_ item: MediaSummary) -> Bool {
        (try? ContentLibraryStore(context: viewContext).isInWatchlist(item)) ?? false
    }

    private func trackedItem(for item: MediaSummary) -> NSManagedObject? {
        let stableLocalID = ContentLibraryStore.stableLocalID(for: item)
        return trackedItems.first { trackedItem in
            guard trackedItem.stringValue(forKey: "kindRaw") == item.kind.rawValue else {
                return false
            }

            if trackedItem.stringValue(forKey: "localID") == stableLocalID {
                return true
            }

            if let tvdbID = item.contentIDs.tvdbID, trackedItem.intValue(forKey: "tvdbID") == tvdbID {
                return true
            }

            if let tmdbID = item.contentIDs.tmdbID, trackedItem.intValue(forKey: "tmdbID") == tmdbID {
                return true
            }

            if let imdbID = item.contentIDs.imdbID, imdbID.isEmpty == false,
               trackedItem.stringValue(forKey: "imdbID") == imdbID {
                return true
            }

            return false
        }
    }

    private func addToLibrary(_ item: MediaSummary) {
        do {
            _ = try ContentLibraryStore(context: viewContext).addToLibrary(item)
            actionMessage = CinueCopy.Discover.addedToLibrary
        } catch {
            actionMessage = "Could not add \(item.title)."
        }
    }

    private func addToWatchlist(_ item: MediaSummary) {
        do {
            try ContentLibraryStore(context: viewContext).addToWatchlist(item)
            actionMessage = CinueCopy.Discover.addedToWatchlist
        } catch {
            actionMessage = "Could not update Watchlist."
        }
    }
}

#Preview {
    NavigationStack {
        DiscoverView()
            .environment(AppEnvironment.preview())
    }
}

private struct DiscoverCategoryRow: View {
    let selectedCategory: DiscoverCategory?
    let isLoading: Bool
    let browseAction: (DiscoverCategory) -> Void

    var body: some View {
        HStack(spacing: CinueSpacing.xs) {
            ForEach(DiscoverCategory.allCases) { category in
                Button {
                    browseAction(category)
                } label: {
                    DiscoverCategoryChip(
                        category: category,
                        isSelected: category == selectedCategory,
                        isLoading: isLoading && category == selectedCategory
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiscoverCategoryChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let category: DiscoverCategory
    let isSelected: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: CinueSpacing.xs) {
            CinueIconTile(symbol: category.symbol, tone: isSelected ? .primary : .neutral, size: 18)

            Text(compactTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 6)
        .cinueCompactGlassControl(cornerRadius: 19, tone: .primary, isSelected: isSelected)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var compactTitle: String {
        switch category {
        case .trending:
            return "Trending"
        case .popularShows:
            return "Shows"
        case .popularMovies:
            return "Movies"
        case .upcomingMovies:
            return "Upcoming"
        }
    }

    private var tileBackground: Color {
        if isSelected {
            return CinueColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.13)
        }

        return colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.86)
    }

    private var tileBorder: Color {
        isSelected ? CinueColors.accentBlue.opacity(0.34) : (colorScheme == .dark ? .white.opacity(0.08) : CinueColors.accentBlue.opacity(0.10))
    }
}

private struct DiscoverMessageRow: View {
    let message: String
    let symbol: String
    let tone: CinueIconTone

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            CinueIconTile(symbol: symbol, tone: tone, size: 32)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(CinueSpacing.md)
        .cinueGlass(cornerRadius: CinueRadius.lg)
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoverResultRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: MediaSummary
    let isTracked: Bool
    let addAction: () -> Void
    let previewAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CinueSpacing.md) {
            HStack(alignment: .top, spacing: CinueSpacing.md) {
                CinuePosterImage(url: item.posterURL, kind: item.kind, width: 54, height: 78)

                VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                    Text(item.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)

                    HStack(spacing: CinueSpacing.sm) {
                        Text(item.kind.rawValue.capitalized)
                        Text(item.attribution.providerName)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryTextColor)

                    if let overview = item.overview, overview.isEmpty == false {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(3)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: previewAction)

            Spacer(minLength: 0)

            Button(action: addAction) {
                Image(systemName: isTracked ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isTracked ? CinueColors.watchedGreen : CinueColors.accentBlue)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isTracked)
            .accessibilityLabel(isTracked ? CinueCopy.Discover.inLibrary : "Add to Library")
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface()
    }

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.82) : .white.opacity(0.86)
    }

    private var rowBorder: Color {
        colorScheme == .dark ? .white.opacity(0.08) : CinueColors.accentBlue.opacity(0.10)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private struct DiscoverItemPreviewSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let item: MediaSummary
    let isTracked: Bool
    let isInWatchlist: Bool
    let actionMessage: String?
    let addToLibrary: () -> Void
    let addToWatchlist: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                    HStack(alignment: .top, spacing: CinueSpacing.md) {
                        CinuePosterImage(url: item.posterURL, kind: item.kind, width: 92, height: 138)

                        VStack(alignment: .leading, spacing: CinueSpacing.sm) {
                            Text(item.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(primaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(item.kind.rawValue.capitalized) - \(item.attribution.providerName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(secondaryTextColor)

                            if isTracked {
                                Label(CinueCopy.Discover.inLibrary, systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CinueColors.watchedGreen)
                            }

                            if isInWatchlist {
                                Label(CinueCopy.Discover.onWatchlist, systemImage: "bookmark.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CinueColors.accentBlue)
                            }
                        }
                    }

                    if let overview = item.overview, overview.isEmpty == false {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(secondaryTextColor)
                    }

                    if let actionMessage {
                        DiscoverMessageRow(message: actionMessage, symbol: "checkmark.circle.fill", tone: .privacy)
                    }

                    VStack(spacing: CinueSpacing.sm) {
                        Button {
                            addToLibrary()
                        } label: {
                            Label(isTracked ? CinueCopy.Discover.inLibrary : "Add to Library", systemImage: isTracked ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTracked)

                        Button {
                            addToWatchlist()
                        } label: {
                            Label(isInWatchlist ? CinueCopy.Discover.onWatchlist : CinueCopy.MovieDetail.addToWatchlistAction, systemImage: isInWatchlist ? "bookmark.fill" : "bookmark")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isInWatchlist)
                    }

                    Text(item.attribution.requiredText)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(CinueSpacing.lg)
            }
            .background(backgroundColor)
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }
}

private extension NSManagedObject {
    func stringValue(forKey key: String, fallback: String = "") -> String {
        value(forKey: key) as? String ?? fallback
    }

    func intValue(forKey key: String) -> Int? {
        guard let number = value(forKey: key) as? NSNumber else {
            return nil
        }

        return number.intValue
    }
}
