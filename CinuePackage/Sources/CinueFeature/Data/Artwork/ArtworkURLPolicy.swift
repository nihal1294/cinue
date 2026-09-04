import Foundation

struct ArtworkLimits: Equatable, Sendable {
    static let standard = ArtworkLimits(
        maximumEncodedBytes: 8 * 1_024 * 1_024,
        maximumImageSide: 8_192,
        maximumPixelCount: 32_000_000,
        maximumRenderedSide: 2_048
    )

    let maximumEncodedBytes: Int
    let maximumImageSide: Int
    let maximumPixelCount: Int
    let maximumRenderedSide: Int
}

enum ArtworkLoadingError: Error, Equatable, Sendable {
    case disallowedURL
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge(actual: Int, maximum: Int)
    case unsupportedMIMEType(String?)
    case mimeTypeMismatch
    case invalidImage
    case pixelLimitExceeded(width: Int, height: Int)
    case animatedImageNotSupported
}

struct ArtworkURLPolicy: Equatable, Sendable {
    let approvedHosts: Set<String>

    static let tmdb = ArtworkURLPolicy(approvedHosts: ["image.tmdb.org"])

    func canonicalURL(for candidate: URL) throws -> URL {
        guard var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let rawHost = components.host,
              components.user == nil,
              components.password == nil,
              components.path.isEmpty == false
        else {
            throw ArtworkLoadingError.disallowedURL
        }

        let host = rawHost.lowercased()
        guard approvedHosts.contains(host),
              isIPAddressLiteral(host) == false,
              components.port == nil || components.port == 443
        else {
            throw ArtworkLoadingError.disallowedURL
        }

        components.scheme = "https"
        components.host = host
        components.port = nil
        components.fragment = nil

        guard let url = components.url else {
            throw ArtworkLoadingError.disallowedURL
        }

        return url
    }

    private func isIPAddressLiteral(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }

        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        return components.count == 4 && components.allSatisfy { part in
            guard part.isEmpty == false, part.allSatisfy(\.isNumber), let value = Int(part) else {
                return false
            }
            return (0...255).contains(value)
        }
    }
}
