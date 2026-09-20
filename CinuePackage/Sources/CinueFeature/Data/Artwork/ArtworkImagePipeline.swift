import Foundation
import UIKit

struct ArtworkLoadRequest: Hashable, Sendable {
    let url: URL
    let maximumPixelSize: Int
}

struct ArtworkImage: @unchecked Sendable {
    let value: UIImage
}

enum ArtworkDecodedImageCost {
    static func value(for image: UIImage) -> Int? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        return value(for: cgImage)
    }

    static func value(for image: CGImage) -> Int? {
        guard image.bytesPerRow > 0, image.height > 0 else {
            return nil
        }

        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return overflow ? nil : cost
    }
}

protocol ArtworkImageLoading: Sendable {
    func image(for request: ArtworkLoadRequest) async throws -> ArtworkImage
}

actor ArtworkImagePipeline: ArtworkImageLoading {
    private let policy: ArtworkURLPolicy
    private let limits: ArtworkLimits
    private let fetcher: any ArtworkFetching
    private let decoder: any ArtworkImageDecoding
    private let encodedCache: URLCache
    private let decodedCache: NSCache<NSString, UIImage>

    init(
        policy: ArtworkURLPolicy = .tmdb,
        limits: ArtworkLimits = .standard,
        fetcher: any ArtworkFetching,
        decoder: any ArtworkImageDecoding,
        encodedCache: URLCache,
        decodedCache: NSCache<NSString, UIImage>
    ) {
        self.policy = policy
        self.limits = limits
        self.fetcher = fetcher
        self.decoder = decoder
        self.encodedCache = encodedCache
        self.decodedCache = decodedCache
    }

    static func live() -> ArtworkImagePipeline {
        let policy = ArtworkURLPolicy.tmdb
        let limits = ArtworkLimits.standard
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let encodedCache = URLCache(
            memoryCapacity: 16 * 1_024 * 1_024,
            diskCapacity: 128 * 1_024 * 1_024,
            diskPath: "CinueArtwork"
        )
        let decodedCache = NSCache<NSString, UIImage>()
        decodedCache.countLimit = 128
        decodedCache.totalCostLimit = 64 * 1_024 * 1_024

        return ArtworkImagePipeline(
            policy: policy,
            limits: limits,
            fetcher: URLSessionArtworkFetcher(
                policy: policy,
                limits: limits,
                session: URLSession(configuration: sessionConfiguration)
            ),
            decoder: ImageIOArtworkDecoder(),
            encodedCache: encodedCache,
            decodedCache: decodedCache
        )
    }

    func image(for request: ArtworkLoadRequest) async throws -> ArtworkImage {
        try Task.checkCancellation()
        let canonicalURL = try policy.canonicalURL(for: request.url)
        let targetPixelSize = min(max(1, request.maximumPixelSize), limits.maximumRenderedSide)
        let cacheKey = "\(canonicalURL.absoluteString)|\(targetPixelSize)" as NSString

        if let cachedImage = decodedCache.object(forKey: cacheKey) {
            try Task.checkCancellation()
            return ArtworkImage(value: cachedImage)
        }

        var urlRequest = URLRequest(url: canonicalURL)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 20
        if let cachedResponse = encodedCache.cachedResponse(for: urlRequest) {
            do {
                try Task.checkCancellation()
                let image = try decode(
                    data: cachedResponse.data,
                    response: cachedResponse.response,
                    maximumPixelSize: targetPixelSize
                )
                try Task.checkCancellation()
                cache(image, for: cacheKey)
                return ArtworkImage(value: image)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                encodedCache.removeCachedResponse(for: urlRequest)
            }
        }

        let payload = try await fetcher.fetch(urlRequest)
        try Task.checkCancellation()
        let image = try decode(
            data: payload.data,
            response: payload.response,
            maximumPixelSize: targetPixelSize
        )
        try Task.checkCancellation()
        encodedCache.storeCachedResponse(
            CachedURLResponse(response: payload.response, data: payload.data),
            for: urlRequest
        )
        cache(image, for: cacheKey)
        return ArtworkImage(value: image)
    }

    private func decode(
        data: Data,
        response: URLResponse,
        maximumPixelSize: Int
    ) throws -> UIImage {
        guard data.count <= limits.maximumEncodedBytes else {
            throw ArtworkLoadingError.responseTooLarge(
                actual: data.count,
                maximum: limits.maximumEncodedBytes
            )
        }

        let httpResponse = try ArtworkHTTPResponseValidator.validated(
            response,
            policy: policy,
            limits: limits
        )
        return try decoder.decode(
            data,
            mimeType: httpResponse.mimeType,
            maximumPixelSize: maximumPixelSize,
            limits: limits
        )
    }

    private func cache(_ image: UIImage, for key: NSString) {
        guard let cost = ArtworkDecodedImageCost.value(for: image) else {
            return
        }

        decodedCache.setObject(image, forKey: key, cost: cost)
    }
}

struct DisabledArtworkImageLoader: ArtworkImageLoading {
    func image(for request: ArtworkLoadRequest) async throws -> ArtworkImage {
        throw ArtworkLoadingError.invalidResponse
    }
}
