import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct DiscoverModelTests {
    @Test
    func searchTrimsQueryAndStoresResults() async throws {
        let provider = RecordingMetadataProvider(results: [
            MediaSummary(
                contentIDs: ContentIDs(localID: "movie-1", tmdbID: 550),
                kind: .movie,
                title: "Fight Club",
                attribution: .tmdb
            )
        ])
        let model = DiscoverModel(provider: provider)
        model.query = "  fight club  "

        await model.search()

        #expect(provider.queries == ["fight club"])
        #expect(model.results.map(\.title) == ["Fight Club"])
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }

    @Test
    func searchShowsProviderKeyMessageWhenTMDBKeyIsMissing() async {
        let provider = RecordingMetadataProvider(error: MetadataProviderError.missingAPIKey)
        let model = DiscoverModel(provider: provider)
        model.query = "severance"

        await model.search()

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "Add a TMDB API key or read token in Settings > Provider Keys.")
        #expect(model.isSearching == false)
    }

    @Test
    func searchShowsProviderKeyMessageWhenTMDBKeyIsInvalid() async {
        let provider = RecordingMetadataProvider(error: MetadataProviderError.invalidCredential)
        let model = DiscoverModel(provider: provider)
        model.query = "severance"

        await model.search()

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "The saved TMDB key was rejected. Check the key in Settings > Provider Keys.")
        #expect(model.isSearching == false)
    }

    @Test
    func searchShowsRateLimitMessageWhenTMDBThrottlesRequests() async {
        let provider = RecordingMetadataProvider(error: MetadataProviderError.rateLimited)
        let model = DiscoverModel(provider: provider)
        model.query = "severance"

        await model.search()

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "TMDB is rate limiting requests. Wait a moment, then try again.")
        #expect(model.isSearching == false)
    }

    @Test
    func searchShowsInvalidResponseMessageWhenTMDBReturnsUnexpectedData() async {
        let provider = RecordingMetadataProvider(error: MetadataProviderError.invalidResponse)
        let model = DiscoverModel(provider: provider)
        model.query = "severance"

        await model.search()

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "TMDB returned data Cinue could not read. Try again later.")
        #expect(model.isSearching == false)
    }

    @Test
    func searchShowsNetworkMessageWhenTMDBIsUnavailable() async {
        let provider = RecordingMetadataProvider(error: MetadataProviderError.providerUnavailable)
        let model = DiscoverModel(provider: provider)
        model.query = "severance"

        await model.search()

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == "TMDB is unavailable or the network is offline. Try again later.")
        #expect(model.isSearching == false)
    }

    @Test
    func emptySearchClearsResultsAndError() async {
        let provider = RecordingMetadataProvider(results: [])
        let model = DiscoverModel(provider: provider)
        model.query = "   "
        model.results = [
            MediaSummary(
                contentIDs: ContentIDs(localID: "show-1", tmdbID: 1399),
                kind: .show,
                title: "Game of Thrones",
                attribution: .tmdb
            )
        ]
        model.errorMessage = "Previous error"
        model.selectedCategory = .popularMovies

        await model.search()

        #expect(provider.queries.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
        #expect(model.selectedCategory == nil)
    }

    @Test
    func clearSearchResetsQueryResultsAndError() {
        let provider = RecordingMetadataProvider(results: [])
        let model = DiscoverModel(provider: provider)
        model.query = "severance"
        model.results = [
            MediaSummary(
                contentIDs: ContentIDs(localID: "show-1", tmdbID: 95396),
                kind: .show,
                title: "Severance",
                attribution: .tmdb
            )
        ]
        model.errorMessage = "Previous error"
        model.isSearching = true
        model.selectedCategory = .popularMovies

        model.clearSearch()

        #expect(model.query.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
        #expect(model.selectedCategory == nil)
    }

    @Test
    func browseStoresSelectedCategoryAndResults() async throws {
        let provider = RecordingMetadataProvider(results: [
            MediaSummary(
                contentIDs: ContentIDs(localID: "show-1", tmdbID: 95396),
                kind: .show,
                title: "Severance",
                attribution: .tmdb
            )
        ])
        let model = DiscoverModel(provider: provider)

        await model.browse(.popularShows)

        #expect(provider.categories == [.popularShows])
        #expect(model.selectedCategory == .popularShows)
        #expect(model.results.map(\.title) == ["Severance"])
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }

    @Test
    func staleSearchCompletionDoesNotReplaceNewerSearchResults() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "older"
        let olderSearch = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.query = "newer"
        let newerSearch = Task { await model.search() }
        await provider.waitForRequestCount(2)

        provider.completeSearch(query: "newer", with: .success([summary(title: "Newer")]))
        await newerSearch.value
        provider.completeSearch(query: "older", with: .success([summary(title: "Older")]))
        await olderSearch.value

        #expect(model.results.map(\.title) == ["Newer"])
    }

    @Test
    func staleBrowseCompletionDoesNotReplaceTheLatestCategory() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        let olderBrowse = Task { await model.browse(.popularShows) }
        await provider.waitForRequestCount(1)

        let newerBrowse = Task { await model.browse(.popularMovies) }
        await provider.waitForRequestCount(2)

        provider.completeBrowse(category: .popularMovies, with: .success([summary(title: "Newer Movies")]))
        await newerBrowse.value
        provider.completeBrowse(category: .popularShows, with: .success([summary(title: "Older Shows")]))
        await olderBrowse.value

        #expect(model.selectedCategory == .popularMovies)
        #expect(model.results.map(\.title) == ["Newer Movies"])
    }

    @Test
    func staleFailureDoesNotClearNewerSuccessfulSearch() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "older"
        let olderSearch = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.query = "newer"
        let newerSearch = Task { await model.search() }
        await provider.waitForRequestCount(2)

        provider.completeSearch(query: "newer", with: .success([summary(title: "Newer")]))
        await newerSearch.value
        provider.completeSearch(query: "older", with: .failure(MetadataProviderError.providerUnavailable))
        await olderSearch.value

        #expect(model.results.map(\.title) == ["Newer"])
        #expect(model.errorMessage == nil)
    }

    @Test
    func clearSearchInvalidatesPendingSearch() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "pending"
        let search = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.clearSearch()
        provider.completeSearch(query: "pending", with: .success([summary(title: "Late")]))
        await search.value

        #expect(model.query.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }

    @Test
    func emptySearchInvalidatesPendingSearch() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "pending"
        let pendingSearch = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.query = "   "
        await model.search()
        provider.completeSearch(query: "pending", with: .success([summary(title: "Late")]))
        await pendingSearch.value

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }

    @Test
    func staleCompletionDoesNotClearTheCurrentSearchLoadingState() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "older"
        let olderSearch = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.query = "newer"
        let newerSearch = Task { await model.search() }
        await provider.waitForRequestCount(2)

        provider.completeSearch(query: "older", with: .success([summary(title: "Older")]))
        await olderSearch.value

        #expect(model.isSearching)

        provider.completeSearch(query: "newer", with: .success([summary(title: "Newer")]))
        await newerSearch.value
        #expect(model.isSearching == false)
    }

    @Test
    func editingQueryInvalidatesAnInFlightSearchEvenWhenChangedBack() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "severance"
        let search = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.query = "silo"
        model.query = "severance"
        provider.completeSearch(query: "severance", with: .success([summary(title: "Late Result")]))
        await search.value

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }

    @Test
    func editingQueryPreventsAnInFlightSearchFailureFromSettingAnError() async {
        let provider = ControlledMetadataProvider()
        let model = DiscoverModel(provider: provider)
        model.query = "severance"
        let search = Task { await model.search() }
        await provider.waitForRequestCount(1)

        model.query = "silo"
        provider.completeSearch(query: "severance", with: .failure(MetadataProviderError.providerUnavailable))
        await search.value

        #expect(model.results.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.isSearching == false)
    }
}

private func summary(title: String) -> MediaSummary {
    MediaSummary(
        contentIDs: ContentIDs(localID: title, tmdbID: title.hashValue),
        kind: .show,
        title: title,
        attribution: .tmdb
    )
}

private final class RecordingMetadataProvider: MetadataProvider, @unchecked Sendable {
    let providerID: MetadataProviderID = .tmdb
    private let lock = NSLock()
    private var storedQueries: [String] = []

    var queries: [String] {
        lock.withLock { storedQueries }
    }

    var categories: [DiscoverCategory] {
        lock.withLock { storedCategories }
    }

    private let results: [MediaSummary]
    private let error: Error?
    private var storedCategories: [DiscoverCategory] = []

    init(results: [MediaSummary] = [], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func search(query: String) async throws -> [MediaSummary] {
        lock.withLock {
            storedQueries.append(query)
        }

        if let error {
            throw error
        }

        return results
    }

    func browse(category: DiscoverCategory) async throws -> [MediaSummary] {
        lock.withLock {
            storedCategories.append(category)
        }

        if let error {
            throw error
        }

        return results
    }
}

private final class ControlledMetadataProvider: MetadataProvider, @unchecked Sendable {
    private enum Request: Equatable {
        case search(String)
        case browse(DiscoverCategory)
    }

    private struct PendingRequest {
        let request: Request
        let continuation: CheckedContinuation<Result<[MediaSummary], Error>, Never>
    }

    let providerID: MetadataProviderID = .tmdb
    private let lock = NSLock()
    private var pendingRequests: [PendingRequest] = []
    private var requestCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func search(query: String) async throws -> [MediaSummary] {
        try await request(.search(query))
    }

    func browse(category: DiscoverCategory) async throws -> [MediaSummary] {
        try await request(.browse(category))
    }

    func waitForRequestCount(_ count: Int) async {
        let shouldWait = lock.withLock { pendingRequests.count < count }
        guard shouldWait else {
            return
        }

        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                guard pendingRequests.count < count else {
                    return true
                }

                requestCountWaiters.append((count, continuation))
                return false
            }

            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func completeSearch(query: String, with result: Result<[MediaSummary], Error>) {
        complete(.search(query), with: result)
    }

    func completeBrowse(category: DiscoverCategory, with result: Result<[MediaSummary], Error>) {
        complete(.browse(category), with: result)
    }

    private func request(_ request: Request) async throws -> [MediaSummary] {
        let result = await withCheckedContinuation { continuation in
            let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                pendingRequests.append(PendingRequest(request: request, continuation: continuation))
                let readyWaiters = requestCountWaiters.filter { pendingRequests.count >= $0.count }
                requestCountWaiters.removeAll { pendingRequests.count >= $0.count }
                return readyWaiters.map(\.continuation)
            }
            waiters.forEach { $0.resume() }
        }

        return try result.get()
    }

    private func complete(_ request: Request, with result: Result<[MediaSummary], Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Result<[MediaSummary], Error>, Never>? in
            guard let index = pendingRequests.firstIndex(where: { $0.request == request }) else {
                return nil
            }

            return pendingRequests.remove(at: index).continuation
        }
        continuation?.resume(returning: result)
    }
}
