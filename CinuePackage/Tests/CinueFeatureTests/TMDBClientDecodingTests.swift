import Foundation
import Testing
@testable import CinueFeature

struct TMDBClientDecodingTests {
    @Test
    func mapsEveryTMDBArtworkVariantToW500() {
        #expect(
            TMDBArtworkURL.make(path: "/poster.jpg", size: .poster)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/poster.jpg"
        )
        #expect(
            TMDBArtworkURL.make(path: "/backdrop.jpg", size: .backdrop)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/backdrop.jpg"
        )
        #expect(
            TMDBArtworkURL.make(path: "/episode-still.jpg", size: .backdrop)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/episode-still.jpg"
        )
        #expect(
            TMDBArtworkURL.make(path: "/profile.jpg", size: .poster)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/profile.jpg"
        )
        #expect(
            TMDBArtworkURL.make(path: "/similar.jpg", size: .poster)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/similar.jpg"
        )
    }

    @Test
    func mapsMovieSearchResult() throws {
        let result = TMDBSearchResult(
            id: 550,
            mediaType: "movie",
            title: "Fight Club",
            name: nil,
            overview: "Overview",
            releaseDate: "1999-10-15",
            firstAirDate: nil,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg"
        )

        let summary = try #require(TMDBClient.map(result))

        #expect(summary.kind == .movie)
        #expect(summary.title == "Fight Club")
        #expect(summary.contentIDs.tmdbID == 550)
        #expect(summary.attribution.providerID == .tmdb)
        #expect(summary.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    @Test
    func mapsTVSearchResult() throws {
        let result = TMDBSearchResult(
            id: 1399,
            mediaType: "tv",
            title: nil,
            name: "Game of Thrones",
            overview: "Overview",
            releaseDate: nil,
            firstAirDate: "2011-04-17",
            posterPath: "/tv-poster.jpg",
            backdropPath: "/tv-backdrop.jpg"
        )

        let summary = try #require(TMDBClient.map(result))

        #expect(summary.kind == .show)
        #expect(summary.title == "Game of Thrones")
        #expect(summary.contentIDs.tmdbID == 1399)
        #expect(summary.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w500/tv-backdrop.jpg")
    }

    @Test
    func ignoresUnsupportedMediaTypes() {
        let result = TMDBSearchResult(
            id: 1,
            mediaType: "person",
            title: nil,
            name: "Actor",
            overview: nil,
            releaseDate: nil,
            firstAirDate: nil,
            posterPath: nil,
            backdropPath: nil
        )

        #expect(TMDBClient.map(result) == nil)
    }

    @Test
    func searchUsesBearerTokenAndMultiSearchEndpoint() async throws {
        let recorder = RequestRecorder()
        let response = """
        {
          "page": 1,
          "results": [
            {
              "id": 550,
              "media_type": "movie",
              "title": "Fight Club",
              "overview": "Overview",
              "release_date": "1999-10-15",
              "poster_path": "/poster.jpg",
              "backdrop_path": "/backdrop.jpg"
            },
            {
              "id": 1399,
              "media_type": "tv",
              "name": "Game of Thrones",
              "overview": "Overview",
              "first_air_date": "2011-04-17",
              "poster_path": "/tv-poster.jpg",
              "backdrop_path": "/tv-backdrop.jpg"
            },
            {
              "id": 287,
              "media_type": "person",
              "name": "Brad Pitt"
            }
          ]
        }
        """.data(using: .utf8)!
        let client = TMDBClient(
            apiKey: { "Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature" },
            transport: { request in
                await recorder.record(request)
                return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        let results = try await client.search(query: "fight club")
        let request = try #require(await recorder.recordedRequest())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(results.map(\.title) == ["Fight Club", "Game of Thrones"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(components.scheme == "https")
        #expect(components.host == "api.themoviedb.org")
        #expect(components.path == "/3/search/multi")
        #expect(components.queryItemValue("query") == "fight club")
        #expect(components.queryItemValue("include_adult") == "false")
        #expect(components.queryItemValue("page") == "1")
        #expect(components.queryItemValue("api_key") == nil)
    }

    @Test
    func searchUsesV3APIKeyAsQueryItem() async throws {
        let recorder = RequestRecorder()
        let response = """
        {
          "page": 1,
          "results": []
        }
        """.data(using: .utf8)!
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { request in
                await recorder.record(request)
                return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        _ = try await client.search(query: "from")
        let request = try #require(await recorder.recordedRequest())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(components.path == "/3/search/multi")
        #expect(components.queryItemValue("query") == "from")
        #expect(components.queryItemValue("api_key") == "1234567890abcdef1234567890abcdef")
    }

    @Test
    func requestsUseConfiguredLanguageCode() async throws {
        let recorder = RequestRecorder()
        let response = """
        {
          "page": 1,
          "results": []
        }
        """.data(using: .utf8)!
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            languageCode: { "fr-FR" },
            transport: { request in
                await recorder.record(request)
                return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        _ = try await client.search(query: "from")
        let request = try #require(await recorder.recordedRequest())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(components.queryItemValue("language") == "fr-FR")
    }

    @Test
    func searchThrowsMissingAPIKeyForBlankToken() async throws {
        let client = TMDBClient(apiKey: { "   " })

        await #expect(throws: MetadataProviderError.missingAPIKey) {
            _ = try await client.search(query: "anything")
        }
    }

    @Test
    func searchThrowsInvalidCredentialForUnauthorizedStatus() async throws {
        let client = TMDBClient(
            apiKey: { "bad-key" },
            transport: { request in
                (
                    Data(),
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: MetadataProviderError.invalidCredential) {
            _ = try await client.search(query: "anything")
        }
    }

    @Test
    func searchThrowsRateLimitedForTooManyRequests() async throws {
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { request in
                (
                    Data(),
                    HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: MetadataProviderError.rateLimited) {
            _ = try await client.search(query: "anything")
        }
    }

    @Test
    func searchThrowsProviderUnavailableForTransportFailure() async throws {
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        await #expect(throws: MetadataProviderError.providerUnavailable) {
            _ = try await client.search(query: "anything")
        }
    }

    @Test
    func searchThrowsInvalidResponseForInvalidJSON() async throws {
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { request in
                (
                    Data("{".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: MetadataProviderError.invalidResponse) {
            _ = try await client.search(query: "anything")
        }
    }

    @Test
    func tvDetailsUseSeriesEndpointAndExposeStatusAndNextEpisode() async throws {
        let recorder = RequestRecorder()
        let response = """
        {
          "id": 68421,
          "name": "Altered Carbon",
          "overview": "A stack returns.",
          "first_air_date": "2018-02-02",
          "poster_path": "/poster.jpg",
          "backdrop_path": "/backdrop.jpg",
          "status": "Returning Series",
          "next_episode_to_air": {
            "id": 1401625,
            "name": "Fresh Upload",
            "overview": "A new case arrives.",
            "air_date": "2026-05-01",
            "season_number": 1,
            "episode_number": 3,
            "still_path": "/episode.jpg"
          }
        }
        """.data(using: .utf8)!
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { request in
                await recorder.record(request)
                return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        let details = try await client.details(kind: .show, tmdbID: 68421)
        let request = try #require(await recorder.recordedRequest())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(components.path == "/3/tv/68421")
        #expect(components.queryItemValue("append_to_response") == "credits,videos,similar")
        #expect(details.title == "Altered Carbon")
        #expect(details.providerStatus == "Returning Series")
        #expect(details.normalizedProviderStatus == "Continuing")
        #expect(details.episodes.map(\.title) == ["Fresh Upload"])
        #expect(details.episodes.first?.seasonNumber == 1)
        #expect(details.episodes.first?.episodeNumber == 3)
    }

    @Test
    func movieDetailsUseMovieEndpoint() async throws {
        let recorder = RequestRecorder()
        let response = """
        {
          "id": 19913,
          "title": "(500) Days of Summer",
          "overview": "A romance is remembered.",
          "release_date": "2009-07-17",
          "poster_path": "/movie.jpg",
          "backdrop_path": "/movie-backdrop.jpg"
        }
        """.data(using: .utf8)!
        let client = TMDBClient(
            apiKey: { "1234567890abcdef1234567890abcdef" },
            transport: { request in
                await recorder.record(request)
                return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        let details = try await client.details(kind: .movie, tmdbID: 19913)
        let request = try #require(await recorder.recordedRequest())
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))

        #expect(components.path == "/3/movie/19913")
        #expect(components.queryItemValue("append_to_response") == "credits,videos,similar")
        #expect(details.kind == .movie)
        #expect(details.title == "(500) Days of Summer")
        #expect(details.releaseDate != nil)
        #expect(details.episodes.isEmpty)
    }
}

private actor RequestRecorder {
    private var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}

private extension URLComponents {
    func queryItemValue(_ name: String) -> String? {
        queryItems?.first { $0.name == name }?.value
    }
}
