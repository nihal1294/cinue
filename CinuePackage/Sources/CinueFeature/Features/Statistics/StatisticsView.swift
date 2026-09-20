import CoreData
import SwiftUI

enum CinueInsightsLayoutMetrics {
    static let usesSiblingHeaderAndScrollableBody = true
    static let hidesSystemNavigationChrome = true
    static let bodyTopPadding: CGFloat = CinueSpacing.lg
}

struct StatisticsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @FetchRequest private var trackedItems: FetchedResults<NSManagedObject>
    @FetchRequest private var episodeStates: FetchedResults<NSManagedObject>

    init() {
        let itemRequest = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        _trackedItems = FetchRequest(fetchRequest: itemRequest, animation: .default)

        let episodeRequest = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        episodeRequest.sortDescriptors = [NSSortDescriptor(key: "localID", ascending: true)]
        _episodeStates = FetchRequest(fetchRequest: episodeRequest, animation: .default)
    }

    var body: some View {
        let snapshot = statistics

        VStack(spacing: 0) {
            CinueScreenHeader(title: "Insights")
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: CinueSpacing.lg) {
                    StatisticsSection(title: "Shows") {
                        StatisticLargeMetric(title: "Shows", value: snapshot.showsTotal.formatted())
                        StatisticProgressRow(title: CinueCopy.Insights.withReleasedNextEpisodes, value: snapshot.showsWithNextEpisodes, total: snapshot.showsTotal)
                        StatisticProgressRow(title: "Continuing", value: snapshot.continuingShows, total: snapshot.showsTotal)
                        StatisticProgressRow(title: CinueCopy.Insights.finishedWatching, value: snapshot.finishedShows, total: snapshot.showsTotal)
                    }

                    StatisticsSection(title: "Episodes") {
                        StatisticLargeMetric(title: "Episodes", value: snapshot.episodesTotal.formatted())
                        StatisticProgressRow(title: "Watched", value: snapshot.watchedEpisodes, total: snapshot.episodesTotal)
                        StatisticDurationRow(title: CinueCopy.Insights.watchTime, value: snapshot.watchedEpisodeDurationText)
                    }

                    StatisticsSection(title: "Movies") {
                        StatisticLargeMetric(title: "Movies", value: snapshot.moviesTotal.formatted())
                        StatisticProgressRow(title: "Watched", value: snapshot.watchedMovies, total: snapshot.moviesTotal)
                        StatisticDurationRow(title: CinueCopy.Insights.watchTime, value: snapshot.watchedMovieDurationText)
                        StatisticProgressRow(title: "Watchlist", value: snapshot.watchlistMovies, total: snapshot.moviesTotal)
                        StatisticDurationRow(title: CinueCopy.Insights.watchlistRuntime, value: snapshot.watchlistMovieDurationText)
                        StatisticProgressRow(title: "Collection", value: snapshot.collectionMovies, total: snapshot.moviesTotal)
                        StatisticDurationRow(title: CinueCopy.Insights.collectionRuntime, value: snapshot.collectionMovieDurationText)
                    }
                }
                .padding(.horizontal, CinueSpacing.lg)
                .padding(.top, CinueInsightsLayoutMetrics.bodyTopPadding)
                .padding(.bottom, CinueSpacing.xxl)
            }
            .scrollIndicators(.hidden)
            .cinueBottomChromeScrollMargins()
        }
        .background(backgroundColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .cinueCinematicNavigationBar(colorScheme: colorScheme)
    }

    private var statistics: StatisticsSnapshot {
        _ = trackedItems.count
        _ = episodeStates.count
        return StatisticsSnapshotBuilder(context: viewContext).snapshot()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? CinueColors.ink : CinueColors.lightSurface
    }
}

private struct StatisticsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.sm) {
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, CinueSpacing.xs)

            VStack(spacing: CinueSpacing.sm) {
                content()
            }
        }
    }
}

private struct StatisticLargeMetric: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Text(value)
                .font(.system(size: 46, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CinueSpacing.md)
        .cinueContentSurface()
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.88)
    }
}

private struct StatisticProgressRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: CinueSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Text("\(value.formatted())")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(primaryTextColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)

                    Capsule()
                        .fill(CinueColors.accentBlue)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 8)
        }
        .padding(CinueSpacing.md)
        .cinueContentSurface()
    }

    private var progress: CGFloat {
        guard total > 0 else {
            return 0
        }

        return min(max(CGFloat(value) / CGFloat(total), 0), 1)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
    }

    private var rowBackground: Color {
        colorScheme == .dark ? CinueColors.graphiteElevated.opacity(0.78) : .white.opacity(0.88)
    }

    private var trackColor: Color {
        colorScheme == .dark ? .white.opacity(0.16) : CinueColors.lightTextSecondary.opacity(0.18)
    }
}

private struct StatisticDurationRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(CinueSpacing.md)
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

#Preview {
    let environment = AppEnvironment.preview()

    NavigationStack {
        StatisticsView()
            .environment(environment)
            .environment(\.managedObjectContext, environment.persistence.container.viewContext)
    }
}
