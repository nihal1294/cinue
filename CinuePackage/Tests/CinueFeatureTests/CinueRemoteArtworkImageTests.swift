import Foundation
import Testing
@testable import CinueFeature

struct CinueRemoteArtworkImageTests {
    @Test
    @MainActor
    func loaderTreatsCancellationAsCancellationRatherThanFailure() async throws {
        let loader = CinueRemoteArtworkLoader()
        let url = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))

        await loader.load(
            url: url,
            maximumPixelSize: 200,
            pipeline: CancellationArtworkImageLoader()
        )

        let isFailure: Bool
        if case .failure = loader.phase {
            isFailure = true
        } else {
            isFailure = false
        }
        #expect(isFailure == false)
    }

    @Test
    func taskIdentityRestartsForNilToRootAndRootToNilTransitions() throws {
        let rootURL = try #require(URL(string: "https://image.tmdb.org/"))
        let nilIdentity = CinueRemoteArtworkTaskIdentity(url: nil, maximumPixelSize: 200)
        let rootIdentity = CinueRemoteArtworkTaskIdentity(url: rootURL, maximumPixelSize: 200)

        #expect(nilIdentity != rootIdentity)
        #expect(rootIdentity != nilIdentity)
    }
}

private struct CancellationArtworkImageLoader: ArtworkImageLoading {
    func image(for request: ArtworkLoadRequest) async throws -> ArtworkImage {
        throw CancellationError()
    }
}
