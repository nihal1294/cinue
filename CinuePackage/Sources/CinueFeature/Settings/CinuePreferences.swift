import Foundation
import SwiftUI

enum CinuePreferenceKeys {
    static let appearanceMode = "cinue.preferences.appearanceMode"
    static let hideEpisodeSpoilers = "cinue.preferences.hideEpisodeSpoilers"
    static let useExactDates = "cinue.preferences.useExactDates"
    static let tmdbLanguageCode = "cinue.preferences.tmdbLanguageCode"
    static let episodeNotificationsEnabled = "cinue.preferences.episodeNotificationsEnabled"
    static let episodeNotificationLeadTimeSeconds = "cinue.preferences.episodeNotificationLeadTimeSeconds"
}

enum CinueAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func stored(in userDefaults: UserDefaults = .standard) -> CinueAppearanceMode {
        guard let rawValue = userDefaults.string(forKey: CinuePreferenceKeys.appearanceMode),
              let mode = CinueAppearanceMode(rawValue: rawValue) else {
            return .system
        }

        return mode
    }
}

enum CinuePreferences {
    static var appearanceMode: CinueAppearanceMode {
        CinueAppearanceMode.stored()
    }

    static var hideEpisodeSpoilers: Bool {
        UserDefaults.standard.bool(forKey: CinuePreferenceKeys.hideEpisodeSpoilers)
    }

    static var useExactDates: Bool {
        UserDefaults.standard.bool(forKey: CinuePreferenceKeys.useExactDates)
    }

    static var tmdbLanguageCode: String {
        let stored = UserDefaults.standard.string(forKey: CinuePreferenceKeys.tmdbLanguageCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty == false {
            return stored.replacingOccurrences(of: "_", with: "-")
        }

        return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    static var episodeNotificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: CinuePreferenceKeys.episodeNotificationsEnabled)
    }

    static var episodeNotificationLeadTime: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds)
        return stored > 0 ? stored : 0
    }
}
