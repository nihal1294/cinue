import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import CinueFeature

@MainActor
struct ArtworkImageDecoderTests {
    private let decoder = ImageIOArtworkDecoder()
    private let limits = ArtworkLimits(
        maximumEncodedBytes: 1_024 * 1_024,
        maximumImageSide: 1_024,
        maximumPixelCount: 1_024 * 1_024,
        maximumRenderedSide: 512
    )

    @Test
    func decodesValidJPEG() throws {
        let image = try decoder.decode(
            makeJPEG(size: CGSize(width: 400, height: 200)),
            mimeType: "image/jpeg",
            maximumPixelSize: 400,
            limits: limits
        )

        #expect(image.size == CGSize(width: 400, height: 200))
    }

    @Test
    func decodesValidPNG() throws {
        let image = try decoder.decode(
            makePNG(size: CGSize(width: 400, height: 200)),
            mimeType: "image/png",
            maximumPixelSize: 400,
            limits: limits
        )

        #expect(image.size == CGSize(width: 400, height: 200))
    }

    @Test
    func rejectsMissingOrUnsupportedMIMEType() {
        let data = makePNG(size: CGSize(width: 400, height: 200))

        #expect(throws: ArtworkLoadingError.unsupportedMIMEType(nil)) {
            try decoder.decode(data, mimeType: nil, maximumPixelSize: 400, limits: limits)
        }
        #expect(throws: ArtworkLoadingError.unsupportedMIMEType("image/gif")) {
            try decoder.decode(data, mimeType: "image/gif", maximumPixelSize: 400, limits: limits)
        }
    }

    @Test
    func rejectsUnsupportedMIMETypeBeforeParsingMalformedData() {
        #expect(throws: ArtworkLoadingError.unsupportedMIMEType("image/gif")) {
            try decoder.decode(
                Data([0x00]),
                mimeType: "image/gif",
                maximumPixelSize: 400,
                limits: limits
            )
        }
    }

    @Test
    func rejectsMIMETypeMismatch() {
        #expect(throws: ArtworkLoadingError.mimeTypeMismatch) {
            try decoder.decode(
                makeJPEG(size: CGSize(width: 400, height: 200)),
                mimeType: "image/png",
                maximumPixelSize: 400,
                limits: limits
            )
        }
    }

    @Test
    func rejectsImageAbovePixelLimit() {
        let restrictiveLimits = ArtworkLimits(
            maximumEncodedBytes: 1_024 * 1_024,
            maximumImageSide: 300,
            maximumPixelCount: 50_000,
            maximumRenderedSide: 300
        )

        #expect(throws: ArtworkLoadingError.pixelLimitExceeded(width: 400, height: 200)) {
            try decoder.decode(
                makePNG(size: CGSize(width: 400, height: 200)),
                mimeType: "image/png",
                maximumPixelSize: 300,
                limits: restrictiveLimits
            )
        }
    }

    @Test
    func downsamplesWhilePreservingAspectRatio() throws {
        let image = try decoder.decode(
            makePNG(size: CGSize(width: 400, height: 200)),
            mimeType: "image/png",
            maximumPixelSize: 100,
            limits: limits
        )

        #expect(image.size.width <= 100)
        #expect(image.size.height <= 100)
        #expect(abs((image.size.width / image.size.height) - 2) < 0.01)
    }

    @Test
    func rejectsMultiFrameImage() throws {
        #expect(throws: ArtworkLoadingError.animatedImageNotSupported) {
            try decoder.decode(
                try makeAnimatedPNG(),
                mimeType: "image/png",
                maximumPixelSize: 400,
                limits: limits
            )
        }
    }

    private func makeJPEG(size: CGSize) -> Data {
        makeImage(size: size).jpegData(compressionQuality: 1)!
    }

    private func makePNG(size: CGSize) -> Data {
        makeImage(size: size).pngData()!
    }

    private func makeImage(size: CGSize, color: UIColor = .systemTeal) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeAnimatedPNG() throws -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 2, nil)!
        let destinationProperties = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGLoopCount: 0
            ]
        ] as CFDictionary
        let frameProperties = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGDelayTime: 0.1,
                kCGImagePropertyAPNGUnclampedDelayTime: 0.1
            ]
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, destinationProperties)
        CGImageDestinationAddImage(destination, makeImage(size: CGSize(width: 400, height: 200)).cgImage!, frameProperties)
        CGImageDestinationAddImage(destination, makeImage(size: CGSize(width: 400, height: 200), color: .systemPurple).cgImage!, frameProperties)
        #expect(CGImageDestinationFinalize(destination))
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        #expect(CGImageSourceGetCount(try #require(source)) == 2)
        return data as Data
    }
}
