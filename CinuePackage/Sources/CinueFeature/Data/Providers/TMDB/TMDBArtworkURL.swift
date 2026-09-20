import Foundation

enum TMDBArtworkSize: Sendable {
    case poster
    case backdrop

    var pathComponent: String {
        "w500"
    }
}

enum TMDBArtworkURL {
    static func make(path: String?, size: TMDBArtworkSize) -> URL? {
        guard let path else {
            return nil
        }

        let relativePath = path.drop(while: { $0 == "/" })
        guard relativePath.isEmpty == false else {
            return nil
        }

        return URL(string: "https://image.tmdb.org/t/p/\(size.pathComponent)/\(relativePath)")
    }
}
