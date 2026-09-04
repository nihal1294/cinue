import Foundation
import Testing
@testable import CinueFeature

struct ArtworkHTTPClientTests {
    private let policy = ArtworkURLPolicy.tmdb
    private let limits = ArtworkLimits(
        maximumEncodedBytes: 8,
        maximumImageSide: 8,
        maximumPixelCount: 64,
        maximumRenderedSide: 8
    )

    @Test
    func redirectDelegateAllowsApprovedRedirect() throws {
        let delegate = ArtworkRedirectDelegate(policy: policy)
        let request = URLRequest(url: try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")))

        #expect(delegate.redirectedRequest(for: request)?.url?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    @Test
    func redirectDelegateRejectsCrossHostRedirect() throws {
        let delegate = ArtworkRedirectDelegate(policy: policy)
        let request = URLRequest(url: try #require(URL(string: "https://evil.example/poster.jpg")))

        #expect(delegate.redirectedRequest(for: request) == nil)
    }

    @Test
    func redirectDelegateRejectsHTTPSDowngrade() throws {
        let delegate = ArtworkRedirectDelegate(policy: policy)
        let request = URLRequest(url: try #require(URL(string: "http://image.tmdb.org/poster.jpg")))

        #expect(delegate.redirectedRequest(for: request) == nil)
    }

    @Test
    func rejectsDisallowedFinalResponseURL() throws {
        let response = try response(url: "https://evil.example/poster.jpg", statusCode: 200)

        #expect(throws: ArtworkLoadingError.disallowedURL) {
            try ArtworkHTTPResponseValidator.validated(response, policy: policy, limits: limits)
        }
    }

    @Test
    func rejectsDeclaredContentLengthAboveLimit() throws {
        let response = try response(
            url: "https://image.tmdb.org/t/p/w500/poster.jpg",
            statusCode: 200,
            headers: ["Content-Length": "9"]
        )

        #expect(throws: ArtworkLoadingError.responseTooLarge(actual: 9, maximum: 8)) {
            try ArtworkHTTPResponseValidator.validated(response, policy: policy, limits: limits)
        }
    }

    @Test
    func boundedCollectorStopsAtEncodedByteLimit() throws {
        var collector = ArtworkByteCollector(maximumByteCount: limits.maximumEncodedBytes)
        try collector.append(Data(repeating: 0, count: 4))

        #expect(throws: ArtworkLoadingError.responseTooLarge(actual: 9, maximum: 8)) {
            try collector.append(Data(repeating: 0, count: 5))
        }
    }

    @Test
    func rejectsNonSuccessHTTPStatus() throws {
        let response = try response(url: "https://image.tmdb.org/t/p/w500/poster.jpg", statusCode: 404)

        #expect(throws: ArtworkLoadingError.httpStatus(404)) {
            try ArtworkHTTPResponseValidator.validated(response, policy: policy, limits: limits)
        }
    }

    @Test
    func headerValidationFailuresCancelBeforeBodyCollection() async throws {
        let cases: [(HTTPURLResponse, ArtworkLoadingError)] = [
            (try response(url: "https://evil.example/poster.jpg", statusCode: 200), .disallowedURL),
            (try response(url: "https://image.tmdb.org/t/p/w500/poster.jpg", statusCode: 404), .httpStatus(404)),
            (
                try response(
                    url: "https://image.tmdb.org/t/p/w500/poster.jpg",
                    statusCode: 200,
                    headers: ["Content-Length": "9"]
                ),
                .responseTooLarge(actual: 9, maximum: 8)
            )
        ]

        for (response, expectedError) in cases {
            let tracker = ArtworkOperationTracker()

            do {
                _ = try await ArtworkHTTPFetchOperation.perform(
                    response: response,
                    policy: policy,
                    limits: limits,
                    cancel: { tracker.cancel() },
                    collect: {
                        tracker.recordCollection()
                        return Data()
                    }
                )
                Issue.record("Expected header validation to reject the payload.")
            } catch let error as ArtworkLoadingError {
                #expect(error == expectedError)
            }

            #expect(tracker.cancellationCount == 1)
            #expect(tracker.collectionCount == 0)
        }
    }

    private func response(
        url: String,
        statusCode: Int,
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        HTTPURLResponse(
            url: try #require(URL(string: url)),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}

private final class ArtworkOperationTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0
    private var collections = 0

    var cancellationCount: Int {
        lock.withLock { cancellations }
    }

    var collectionCount: Int {
        lock.withLock { collections }
    }

    func cancel() {
        lock.withLock {
            cancellations += 1
        }
    }

    func recordCollection() {
        lock.withLock {
            collections += 1
        }
    }
}
