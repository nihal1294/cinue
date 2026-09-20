import Foundation

struct ProviderCredentialSummary: Equatable, Sendable {
    let isConfigured: Bool
    let maskedValue: String

    init(value: String? = nil) {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard trimmedValue.isEmpty == false else {
            isConfigured = false
            maskedValue = "No saved credential"
            return
        }

        isConfigured = true
        maskedValue = Self.mask(trimmedValue)
    }

    var statusText: String {
        isConfigured ? "Configured" : "Not Configured"
    }

    private static func mask(_ value: String) -> String {
        guard value.count > 4 else {
            return "********"
        }

        return "********\(value.suffix(4))"
    }
}
