import ImageIO
import UIKit
import UniformTypeIdentifiers

protocol ArtworkImageDecoding: Sendable {
    func decode(
        _ data: Data,
        mimeType: String?,
        maximumPixelSize: Int,
        limits: ArtworkLimits
    ) throws -> UIImage
}

struct ImageIOArtworkDecoder: ArtworkImageDecoding {
    func decode(
        _ data: Data,
        mimeType: String?,
        maximumPixelSize: Int,
        limits: ArtworkLimits
    ) throws -> UIImage {
        guard let mimeType else {
            throw ArtworkLoadingError.unsupportedMIMEType(nil)
        }

        let normalizedMIMEType = mimeType.lowercased()
        let expectedType: UTType
        switch normalizedMIMEType {
        case "image/jpeg":
            expectedType = .jpeg
        case "image/png":
            expectedType = .png
        default:
            throw ArtworkLoadingError.unsupportedMIMEType(mimeType)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ArtworkLoadingError.invalidImage
        }

        guard CGImageSourceGetCount(source) == 1 else {
            throw ArtworkLoadingError.animatedImageNotSupported
        }

        guard let sourceType = CGImageSourceGetType(source) as String?,
              sourceType == expectedType.identifier
        else {
            throw ArtworkLoadingError.mimeTypeMismatch
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            throw ArtworkLoadingError.invalidImage
        }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard overflow == false,
              width <= limits.maximumImageSide,
              height <= limits.maximumImageSide,
              pixelCount <= limits.maximumPixelCount
        else {
            throw ArtworkLoadingError.pixelLimitExceeded(width: width, height: height)
        }

        let renderedSide = min(maximumPixelSize, limits.maximumRenderedSide)
        guard renderedSide > 0 else {
            throw ArtworkLoadingError.invalidImage
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: renderedSide
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw ArtworkLoadingError.invalidImage
        }

        return UIImage(cgImage: thumbnail)
    }
}
