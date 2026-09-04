import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import CinueFeature

struct ArtworkImagePipelineTests {
    private let url = URL(string: "https://image.tmdb.org/t/p/w500/poster.png")!
    private let limits = ArtworkLimits(
        maximumEncodedBytes: 1_024,
        maximumImageSide: 1_024,
        maximumPixelCount: 1_024 * 1_024,
        maximumRenderedSide: 512
    )

    @Test
    func returnsDecodedMemoryCacheHitWithoutFetching() async throws {
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("valid".utf8)))
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder)
        let request = ArtworkLoadRequest(url: url, maximumPixelSize: 100)

        _ = try await pipeline.image(for: request)
        _ = try await pipeline.image(for: request)

        #expect(await fetcher.callCount == 1)
        #expect(decoder.callCount == 1)
    }

    @Test
    func usesTargetPixelSizeInDecodedCacheKey() async throws {
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("valid".utf8)))
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder)

        _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))
        _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 200))

        #expect(await fetcher.callCount == 1)
        #expect(decoder.callCount == 2)
        #expect(decoder.maximumPixelSizes == [100, 200])
    }

    @Test
    func usesValidatedEncodedCacheBeforeNetwork() async throws {
        let cache = makeEncodedCache()
        let cachedPayload = try payload(data: Data("cached".utf8))
        cache.storeCachedResponse(
            CachedURLResponse(response: cachedPayload.response, data: cachedPayload.data),
            for: cacheRequest()
        )
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("network".utf8)))
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)

        _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))

        #expect(await fetcher.callCount == 0)
        #expect(decoder.dataValues == [Data("cached".utf8)])
    }

    @Test
    func evictsInvalidEncodedCacheAndRefetches() async throws {
        let cache = makeEncodedCache()
        let cachedPayload = try payload(data: Data("invalid".utf8))
        cache.storeCachedResponse(
            CachedURLResponse(response: cachedPayload.response, data: cachedPayload.data),
            for: cacheRequest()
        )
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("network".utf8)))
        let decoder = ArtworkDecodingSpy(failingData: Data("invalid".utf8))
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)

        _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))

        #expect(await fetcher.callCount == 1)
        #expect(decoder.dataValues == [Data("invalid".utf8), Data("network".utf8)])
        #expect(cache.cachedResponse(for: cacheRequest())?.data == Data("network".utf8))
    }

    @Test
    func storesOnlySuccessfullyValidatedPayloads() async throws {
        let cache = makeEncodedCache()
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("invalid-image".utf8)))
        let decoder = ArtworkDecodingSpy(failingData: Data("invalid-image".utf8))
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)

        await #expect(throws: ArtworkLoadingError.invalidImage) {
            _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))
        }

        #expect(cache.cachedResponse(for: cacheRequest()) == nil)
    }

    @Test
    func sendsTwentySecondTimeoutToArtworkFetcher() async throws {
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("valid".utf8)))
        let pipeline = makePipeline(fetcher: fetcher, decoder: ArtworkDecodingSpy())

        _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))

        let request = try #require(await fetcher.lastRequest())
        #expect(request.timeoutInterval == 20)
    }

    @Test
    func doesNotCacheRejectedPayload() async throws {
        let cache = makeEncodedCache()
        let rejected = try payload(url: "https://evil.example/poster.png", data: Data("rejected".utf8))
        let fetcher = ArtworkFetchingSpy(payload: rejected)
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)

        await #expect(throws: ArtworkLoadingError.disallowedURL) {
            _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))
        }

        #expect(cache.cachedResponse(for: cacheRequest()) == nil)
        #expect(decoder.callCount == 0)
    }

    @Test
    func doesNotCacheOversizedPayload() async throws {
        let cache = makeEncodedCache()
        let oversizedData = Data(repeating: 0, count: limits.maximumEncodedBytes + 1)
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: oversizedData))
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)

        await #expect(throws: ArtworkLoadingError.responseTooLarge(actual: 1_025, maximum: 1_024)) {
            _ = try await pipeline.image(for: ArtworkLoadRequest(url: url, maximumPixelSize: 100))
        }

        #expect(cache.cachedResponse(for: cacheRequest()) == nil)
        #expect(decoder.callCount == 0)
    }

    @Test
    func decodedCacheCostUsesActual16BitPNGBackingStorage() throws {
        let image = try makeSixteenBitPNGImage()
        let cost = try #require(ArtworkDecodedImageCost.value(for: image))
        let expectedCost = image.bytesPerRow * image.height

        #expect(image.bitsPerComponent == 16)
        #expect(image.bitsPerPixel == 64)
        #expect(cost == expectedCost)
        #expect(cost > image.width * image.height * 4)
    }

    @Test
    func preCanceledEncodedCacheRequestDoesNotDecode() async throws {
        let cache = makeEncodedCache()
        let cachedPayload = try payload(data: Data("cached".utf8))
        cache.storeCachedResponse(
            CachedURLResponse(response: cachedPayload.response, data: cachedPayload.data),
            for: cacheRequest()
        )
        let fetcher = ArtworkFetchingSpy(payload: try payload(data: Data("network".utf8)))
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)
        let request = ArtworkLoadRequest(url: url, maximumPixelSize: 100)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.image(for: request)
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        #expect(await fetcher.callCount == 0)
        #expect(decoder.callCount == 0)
        #expect(cache.cachedResponse(for: cacheRequest())?.data == Data("cached".utf8))
    }

    @Test
    func cancellationAfterFetchDoesNotDecodeOrCache() async throws {
        let cache = makeEncodedCache()
        let fetcher = ArtworkCancellingFetchingSpy(payload: try payload(data: Data("network".utf8)))
        let decoder = ArtworkDecodingSpy()
        let pipeline = makePipeline(fetcher: fetcher, decoder: decoder, encodedCache: cache)
        let request = ArtworkLoadRequest(url: url, maximumPixelSize: 100)
        let task = Task {
            try await pipeline.image(for: request)
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        #expect(await fetcher.callCount == 1)
        #expect(decoder.callCount == 0)
        #expect(cache.cachedResponse(for: cacheRequest()) == nil)
    }

    private func makePipeline(
        fetcher: any ArtworkFetching,
        decoder: any ArtworkImageDecoding,
        encodedCache: URLCache? = nil
    ) -> ArtworkImagePipeline {
        ArtworkImagePipeline(
            policy: .tmdb,
            limits: limits,
            fetcher: fetcher,
            decoder: decoder,
            encodedCache: encodedCache ?? makeEncodedCache(),
            decodedCache: NSCache<NSString, UIImage>()
        )
    }

    private func makeEncodedCache() -> URLCache {
        URLCache(
            memoryCapacity: 8_192,
            diskCapacity: 8_192,
            diskPath: "ArtworkImagePipelineTests-\(UUID().uuidString)"
        )
    }

    private func cacheRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    private func payload(
        url: String = "https://image.tmdb.org/t/p/w500/poster.png",
        data: Data
    ) throws -> ArtworkHTTPPayload {
        ArtworkHTTPPayload(
            data: data,
            response: HTTPURLResponse(
                url: try #require(URL(string: url)),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "image/png",
                    "Cache-Control": "max-age=3600"
                ]
            )!
        )
    }

    private func makeSixteenBitPNGImage() throws -> CGImage {
        let width = 2
        let height = 2
        let bytesPerRow = width * 8
        let sourceData = Data(repeating: 0xFF, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder16Little)
        let sourceImage = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 64,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: CGDataProvider(data: sourceData as CFData)!,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let encodedData = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(encodedData, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, sourceImage, nil)
        #expect(CGImageDestinationFinalize(destination))

        let source = try #require(CGImageSourceCreateWithData(encodedData as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}

private actor ArtworkFetchingSpy: ArtworkFetching {
    private let payload: ArtworkHTTPPayload
    private(set) var callCount = 0
    private var requests: [URLRequest] = []

    init(payload: ArtworkHTTPPayload) {
        self.payload = payload
    }

    func fetch(_ request: URLRequest) async throws -> ArtworkHTTPPayload {
        callCount += 1
        requests.append(request)
        return payload
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }
}

private actor ArtworkCancellingFetchingSpy: ArtworkFetching {
    private let payload: ArtworkHTTPPayload
    private(set) var callCount = 0

    init(payload: ArtworkHTTPPayload) {
        self.payload = payload
    }

    func fetch(_ request: URLRequest) async throws -> ArtworkHTTPPayload {
        callCount += 1
        withUnsafeCurrentTask { $0?.cancel() }
        return payload
    }
}

private final class ArtworkDecodingSpy: ArtworkImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let failingData: Data?
    private var values: [Data] = []
    private var pixelSizes: [Int] = []

    init(failingData: Data? = nil) {
        self.failingData = failingData
    }

    var callCount: Int {
        lock.withLock { values.count }
    }

    var dataValues: [Data] {
        lock.withLock { values }
    }

    var maximumPixelSizes: [Int] {
        lock.withLock { pixelSizes }
    }

    func decode(
        _ data: Data,
        mimeType: String?,
        maximumPixelSize: Int,
        limits: ArtworkLimits
    ) throws -> UIImage {
        lock.withLock {
            values.append(data)
            pixelSizes.append(maximumPixelSize)
        }
        if data == failingData {
            throw ArtworkLoadingError.invalidImage
        }
        return Self.makeImage()
    }

    private static func makeImage() -> UIImage {
        let data = Data([0, 128, 255, 255])
        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: image)
    }
}
