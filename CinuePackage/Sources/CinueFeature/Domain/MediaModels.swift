import Foundation

enum MediaKind: String, Sendable, Codable, CaseIterable {
    case show
    case movie
}

struct MediaSummary: Identifiable, Hashable, Sendable, Codable {
    var id: String { contentIDs.localID }
    var contentIDs: ContentIDs
    var kind: MediaKind
    var title: String
    var originalTitle: String?
    var overview: String?
    var releaseDate: Date?
    var posterURL: URL?
    var backdropURL: URL?
    var attribution: ProviderAttribution

    init(
        contentIDs: ContentIDs,
        kind: MediaKind,
        title: String,
        originalTitle: String? = nil,
        overview: String? = nil,
        releaseDate: Date? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        attribution: ProviderAttribution
    ) {
        self.contentIDs = contentIDs
        self.kind = kind
        self.title = title
        self.originalTitle = originalTitle
        self.overview = overview
        self.releaseDate = releaseDate
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.attribution = attribution
    }
}
