import Foundation

enum ProviderStatusNormalizer {
    static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        switch trimmed.localizedLowercase {
        case "continuing", "returning series", "in production":
            return "Continuing"
        case "ended", "finished", "completed":
            return "Ended"
        case "canceled", "cancelled":
            return "Cancelled"
        case "planned":
            return "Planned"
        case "pilot":
            return "Pilot"
        default:
            return trimmed
        }
    }
}
