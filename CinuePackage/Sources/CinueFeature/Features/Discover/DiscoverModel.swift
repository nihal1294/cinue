import Foundation
import Observation

@MainActor
@Observable
final class DiscoverModel {
    var query = "" {
        didSet {
            guard query != oldValue else {
                return
            }

            invalidatePendingRequests()
            isSearching = false
        }
    }
    var results: [MediaSummary] = []
    var isSearching = false
    var selectedCategory: DiscoverCategory?
    var errorMessage: String?

    private let provider: any MetadataProvider
    private var requestGeneration = 0

    init(provider: any MetadataProvider) {
        self.provider = provider
    }

    func clearSearch() {
        invalidatePendingRequests()
        query = ""
        results = []
        selectedCategory = nil
        errorMessage = nil
        isSearching = false
    }

    func search() async {
        let generation = beginRequest()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            results = []
            selectedCategory = nil
            errorMessage = nil
            isSearching = false
            return
        }

        isSearching = true
        selectedCategory = nil
        errorMessage = nil

        do {
            let response = try await provider.search(query: trimmedQuery)
            guard generation == requestGeneration else {
                return
            }

            results = response
            isSearching = false
        } catch {
            guard generation == requestGeneration else {
                return
            }

            handleProviderError(error, fallbackMessage: "Search failed. Check the provider key and network connection.")
            isSearching = false
        }
    }

    func browse(_ category: DiscoverCategory) async {
        let generation = beginRequest()
        isSearching = true
        selectedCategory = category
        errorMessage = nil

        do {
            let response = try await provider.browse(category: category)
            guard generation == requestGeneration else {
                return
            }

            results = response
            isSearching = false
        } catch {
            guard generation == requestGeneration else {
                return
            }

            handleProviderError(error, fallbackMessage: "Browse failed. Check the provider key and network connection.")
            isSearching = false
        }
    }

    private func beginRequest() -> Int {
        requestGeneration &+= 1
        return requestGeneration
    }

    private func invalidatePendingRequests() {
        requestGeneration &+= 1
    }

    private func handleProviderError(_ error: Error, fallbackMessage: String) {
        results = []

        guard let providerError = error as? MetadataProviderError else {
            errorMessage = fallbackMessage
            return
        }

        switch providerError {
        case .missingAPIKey:
            errorMessage = "Add a TMDB API key or read token in Settings > Provider Keys."
        case .invalidCredential:
            errorMessage = "The saved TMDB key was rejected. Check the key in Settings > Provider Keys."
        case .rateLimited:
            errorMessage = "TMDB is rate limiting requests. Wait a moment, then try again."
        case .invalidResponse:
            errorMessage = "TMDB returned data Cinue could not read. Try again later."
        case .providerUnavailable:
            errorMessage = "TMDB is unavailable or the network is offline. Try again later."
        }
    }
}
