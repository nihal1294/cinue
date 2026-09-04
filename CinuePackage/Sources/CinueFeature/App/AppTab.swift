import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case now
    case library
    case discover
    case lists
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now:
            "Now"
        case .library:
            "Library"
        case .discover:
            "Discover"
        case .lists:
            "Lists"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .now:
            "bookmark.fill"
        case .library:
            "rectangle.stack.fill"
        case .discover:
            "magnifyingglass.circle.fill"
        case .lists:
            "checklist"
        case .settings:
            "slider.horizontal.3"
        }
    }
}
