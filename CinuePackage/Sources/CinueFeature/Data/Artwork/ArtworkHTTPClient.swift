import Foundation

struct ArtworkHTTPPayload: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol ArtworkFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> ArtworkHTTPPayload
}

final class ArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let policy: ArtworkURLPolicy

    init(policy: ArtworkURLPolicy) {
        self.policy = policy
    }

    func redirectedRequest(for request: URLRequest) -> URLRequest? {
        guard let url = request.url,
              let canonicalURL = try? policy.canonicalURL(for: url)
        else {
            return nil
        }

        var canonicalRequest = request
        canonicalRequest.url = canonicalURL
        return canonicalRequest
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(redirectedRequest(for: request))
    }
}

struct URLSessionArtworkFetcher: ArtworkFetching {
    let policy: ArtworkURLPolicy
    let limits: ArtworkLimits
    let session: URLSession

    func fetch(_ request: URLRequest) async throws -> ArtworkHTTPPayload {
        guard let url = request.url else {
            throw ArtworkLoadingError.invalidResponse
        }

        var canonicalRequest = request
        canonicalRequest.url = try policy.canonicalURL(for: url)

        let redirectDelegate = ArtworkRedirectDelegate(policy: policy)
        let (bytes, response) = try await session.bytes(for: canonicalRequest, delegate: redirectDelegate)
        return try await ArtworkHTTPFetchOperation.perform(
            response: response,
            policy: policy,
            limits: limits,
            cancel: { bytes.task.cancel() },
            collect: {
                var collector = ArtworkByteCollector(maximumByteCount: limits.maximumEncodedBytes)
                for try await byte in bytes {
                    try collector.append(byte)
                }
                return collector.data
            }
        )
    }
}

enum ArtworkHTTPFetchOperation {
    static func perform(
        response: URLResponse,
        policy: ArtworkURLPolicy,
        limits: ArtworkLimits,
        cancel: () -> Void,
        collect: () async throws -> Data
    ) async throws -> ArtworkHTTPPayload {
        do {
            let httpResponse = try ArtworkHTTPResponseValidator.validated(
                response,
                policy: policy,
                limits: limits
            )
            let data = try await collect()
            return ArtworkHTTPPayload(data: data, response: httpResponse)
        } catch {
            cancel()
            throw error
        }
    }
}

enum ArtworkHTTPResponseValidator {
    static func validated(
        _ response: URLResponse,
        policy: ArtworkURLPolicy,
        limits: ArtworkLimits
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArtworkLoadingError.invalidResponse
        }

        guard let url = httpResponse.url else {
            throw ArtworkLoadingError.invalidResponse
        }

        _ = try policy.canonicalURL(for: url)

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ArtworkLoadingError.httpStatus(httpResponse.statusCode)
        }

        let expectedLength = httpResponse.expectedContentLength
        guard expectedLength <= Int64(limits.maximumEncodedBytes) else {
            throw ArtworkLoadingError.responseTooLarge(
                actual: expectedLength > Int64(Int.max) ? Int.max : Int(expectedLength),
                maximum: limits.maximumEncodedBytes
            )
        }

        return httpResponse
    }
}

struct ArtworkByteCollector {
    private(set) var data = Data()
    private let maximumByteCount: Int

    init(maximumByteCount: Int) {
        self.maximumByteCount = max(0, maximumByteCount)
    }

    mutating func append(_ chunk: Data) throws {
        let (actualByteCount, overflow) = data.count.addingReportingOverflow(chunk.count)
        guard overflow == false, actualByteCount <= maximumByteCount else {
            throw ArtworkLoadingError.responseTooLarge(
                actual: overflow ? Int.max : actualByteCount,
                maximum: maximumByteCount
            )
        }

        data.append(chunk)
    }

    mutating func append(_ byte: UInt8) throws {
        guard data.count < maximumByteCount else {
            throw ArtworkLoadingError.responseTooLarge(
                actual: data.count == Int.max ? Int.max : data.count + 1,
                maximum: maximumByteCount
            )
        }

        data.append(byte)
    }
}
