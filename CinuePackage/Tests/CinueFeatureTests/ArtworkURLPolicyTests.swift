import Foundation
import Testing
@testable import CinueFeature

struct ArtworkURLPolicyTests {
    @Test
    func acceptsCanonicalTMDBHTTPSURL() throws {
        let candidate = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))

        #expect(try ArtworkURLPolicy.tmdb.canonicalURL(for: candidate) == candidate)
    }

    @Test
    func canonicalizesDefaultHTTPSPortAndDropsFragment() throws {
        let candidate = try #require(URL(string: "https://IMAGE.TMDB.ORG:443/t/p/w500/poster.jpg#preview"))

        #expect(try ArtworkURLPolicy.tmdb.canonicalURL(for: candidate).absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    @Test
    func rejectsHTTPArtworkURL() throws {
        try expectDisallowed("http://image.tmdb.org/")
    }

    @Test
    func rejectsUnapprovedHost() throws {
        try expectDisallowed("https://evil.example/poster.jpg")
    }

    @Test
    func rejectsHostSuffixConfusion() throws {
        try expectDisallowed("https://image.tmdb.org.evil.example/poster.jpg")
    }

    @Test
    func rejectsUserInfoHostConfusion() throws {
        try expectDisallowed("https://image.tmdb.org@evil.example/poster.jpg")
    }

    @Test
    func rejectsNonDefaultPort() throws {
        try expectDisallowed("https://image.tmdb.org:444/poster.jpg")
    }

    @Test
    func rejectsIPAddressHost() throws {
        try expectDisallowed("https://127.0.0.1/poster.jpg")
    }

    private func expectDisallowed(_ value: String) throws {
        let candidate = try #require(URL(string: value))

        #expect(throws: ArtworkLoadingError.disallowedURL) {
            try ArtworkURLPolicy.tmdb.canonicalURL(for: candidate)
        }
    }
}
