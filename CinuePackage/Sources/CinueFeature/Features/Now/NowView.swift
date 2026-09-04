import CoreData
import SwiftUI

struct NowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var trackedShows: FetchedResults<NSManagedObject>
    @FetchRequest private var episodeStates: FetchedResults<NSManagedObject>
    @State private var selectedSection: NowSection = .upNext
    @State private var actionMessage: String?

    init() {
        let showRequest = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        showRequest.predicate = NSPredicate(format: "kindRaw == %@", MediaKind.show.rawValue)
        showRequest.sortDescriptors = [
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        _trackedShows = FetchRequest(fetchRequest: showRequest, animation: .default)

        let episodeRequest = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        episodeRequest.sortDescriptors = [
            NSSortDescriptor(key: "showLocalID", ascending: true),
            NSSortDescriptor(key: "seasonNumber", ascending: true),
            NSSortDescriptor(key: "episodeNumber", ascending: true),
            NSSortDescriptor(key: "localID", ascending: true)
        ]
        _episodeStates = FetchRequest(fetchRequest: episodeRequest, animation: .default)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            if dashboard.isEmpty {
                emptyNow
            } else {
                nowContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .cinueCinematicNavigationBar(colorScheme: colorScheme)
        .cinueAutoDismissFeedback($actionMessage)
    }

    private var nowContent: some View {
        let snapshot = dashboard
        let items = snapshot.items(for: selectedSection)

        return VStack(spacing: 0) {
            CinueScreenHeader(title: "Now")
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                    NowSummaryRow(
                        snapshot: snapshot,
                        selectedSection: selectedSection,
                        selectionAction: { selectedSection = $0 }
                    )

                    if let actionMessage {
                        NowMessageRow(message: actionMessage)
                    }

                    NowSectionPicker(
                        selectedSection: selectedSection,
                        counts: snapshot.counts,
                        selectionAction: { selectedSection = $0 }
                    )

                    VStack(alignment: .leading, spacing: CinueSpacing.sm) {
                        Text(selectedSection.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .padding(.horizontal, CinueSpacing.xs)

                        if items.isEmpty {
                            NowEmptySection(section: selectedSection)
                        } else {
                            LazyVStack(spacing: CinueSpacing.sm) {
                                ForEach(items) { episode in
                                    NowEpisodeRow(
                                        episode: episode,
                                        showsWatchAction: selectedSection.showsWatchAction && episode.isWatched == false,
                                        markWatchedAction: {
                                            markWatched(episode)
                                        }
                                    )
                                }
                            }
                        }
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

    private var emptyNow: some View {
        CinuePlaceholderScreen(
            title: "Now",
            symbol: "play.circle",
            headline: "Nothing to Watch Yet",
            message: "Import or add shows to build your up-next queue."
        )
    }

    private var dashboard: NowDashboardSnapshot {
        NowSnapshotBuilder(context: viewContext)
            .snapshot(
                trackedShows: Array(trackedShows),
                episodeStates: Array(episodeStates)
            )
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private func markWatched(_ episode: NowEpisodeSnapshot) {
        do {
            try WatchStateStore(context: viewContext).markEpisodeWatched(localID: episode.localID)
            actionMessage = "\(episode.titleLine) marked watched."
        } catch {
            actionMessage = "Could not update watch state."
        }
    }
}

private enum NowSection: String, CaseIterable, Identifiable {
    case upNext
    case history
    case recent
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upNext:
            return "Up Next"
        case .history:
            return "Recently Watched"
        case .recent:
            return "Recently Aired"
        case .upcoming:
            return "Upcoming"
        }
    }

    var symbol: String {
        switch self {
        case .upNext:
            return "play.circle.fill"
        case .history:
            return "clock.arrow.circlepath"
        case .recent:
            return "calendar.badge.clock"
        case .upcoming:
            return "calendar"
        }
    }

    var showsWatchAction: Bool {
        self != .history
    }
}

private extension NowDashboardSnapshot {
    var counts: [NowSection: Int] {
        [
            .upNext: upNext.count,
            .history: recentlyWatched.count,
            .recent: recentlyAired.count,
            .upcoming: upcoming.count
        ]
    }

    func items(for section: NowSection) -> [NowEpisodeSnapshot] {
        switch section {
        case .upNext:
            return upNext
        case .history:
            return recentlyWatched
        case .recent:
            return recentlyAired
        case .upcoming:
            return upcoming
        }
    }
}

private struct NowSummaryRow: View {
    let snapshot: NowDashboardSnapshot
    let selectedSection: NowSection
    let selectionAction: (NowSection) -> Void

    var body: some View {
        HStack(spacing: CinueSpacing.sm) {
            summaryButton(section: .upNext, title: "Next", value: snapshot.upNext.count, symbol: "play.circle.fill", tone: .primary)
            summaryButton(section: .history, title: "Watched", value: snapshot.recentlyWatched.count, symbol: "checkmark.circle.fill", tone: .privacy)
            summaryButton(section: .recent, title: "Recent", value: snapshot.recentlyAired.count, symbol: "calendar.badge.clock", tone: .metadata)
            summaryButton(section: .upcoming, title: "Upcoming", value: snapshot.upcoming.count, symbol: "calendar", tone: .cloud)
        }
    }

    private func summaryButton(section: NowSection, title: String, value: Int, symbol: String, tone: CinueIconTone) -> some View {
        Button {
            selectionAction(section)
        } label: {
            NowSummaryTile(
                title: title,
                value: value,
                symbol: symbol,
                tone: tone,
                isSelected: section == selectedSection
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.title), \(value)")
    }
}

private struct NowSummaryTile: View {
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

private struct NowSectionPicker: View {
    let selectedSection: NowSection
    let counts: [NowSection: Int]
    let selectionAction: (NowSection) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            pickerRow
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
    }

    private var pickerRow: some View {
        HStack(spacing: CinueSpacing.sm) {
            ForEach(NowSection.allCases) { section in
                Button {
                    selectionAction(section)
                } label: {
                    NowSectionPill(
                        title: section.title,
                        symbol: section.symbol,
                        count: counts[section] ?? 0,
                        isSelected: section == selectedSection
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.title), \(counts[section] ?? 0)")
            }
        }
        .padding(.horizontal, CinueSpacing.xs)
        .padding(.vertical, CinueSpacing.xs)
    }
}

private struct NowSectionPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let symbol: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: CinueSpacing.xs) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))

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

private struct NowEpisodeRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let episode: NowEpisodeSnapshot
    let showsWatchAction: Bool
    let markWatchedAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: CinueSpacing.md) {
            NavigationLink(value: route) {
                HStack(alignment: .top, spacing: CinueSpacing.md) {
                    CinuePosterImage(url: episode.showPosterURL, kind: .show, width: 58, height: 86)

                    VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                        Text(episode.showTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(2)

                        Text(episode.titleLine)
                            .font(.subheadline)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(2)

                        HStack(spacing: CinueSpacing.xs) {
                            Text(episode.stateLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(stateColor)

                            if let dateLine = episode.dateLine {
                                Text(dateLine)
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor.opacity(0.84))
                                    .lineLimit(1)
                            }
                        }
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
            } else {
                Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(episode.isWatched ? CinueColors.watchedGreen : secondaryTextColor.opacity(0.65))
            }
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

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.88)
    }

    private var rowBorder: Color {
        colorScheme == .dark ? .white.opacity(0.08) : CinueColors.accentBlue.opacity(0.10)
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

private struct NowMessageRow: View {
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

private struct NowEmptySection: View {
    @Environment(\.colorScheme) private var colorScheme

    let section: NowSection

    var body: some View {
        VStack(spacing: CinueSpacing.xs) {
            Image(systemName: section.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(CinueColors.accentBlue)

            Text("Nothing Here")
                .font(.headline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(CinueSpacing.lg)
        .cinueContentSurface()
    }

    private var emptyMessage: String {
        switch section {
        case .upNext:
            return CinueCopy.Now.upNextEmpty
        case .history:
            return CinueCopy.Now.historyEmpty
        case .recent:
            return CinueCopy.Now.recentEmpty
        case .upcoming:
            return CinueCopy.Now.upcomingEmpty
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
}

#Preview {
    let environment = AppEnvironment.preview()

    NavigationStack {
        NowView()
            .environment(environment)
            .environment(\.managedObjectContext, environment.persistence.container.viewContext)
    }
}
