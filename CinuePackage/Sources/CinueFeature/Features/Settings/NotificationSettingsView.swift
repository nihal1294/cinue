import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(CinuePreferenceKeys.episodeNotificationsEnabled) private var episodeNotificationsEnabled = false
    @AppStorage(CinuePreferenceKeys.episodeNotificationLeadTimeSeconds) private var leadTimeSeconds = 0.0
    @State private var statusMessage = "Schedule local reminders for upcoming unwatched episodes."
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section("Episode Reminders") {
                Toggle("Upcoming Episode Reminders", isOn: $episodeNotificationsEnabled)
                    .onChange(of: episodeNotificationsEnabled) { _, _ in
                        refreshNotifications(requestAuthorizationIfNeeded: episodeNotificationsEnabled)
                    }

                Picker("Remind", selection: $leadTimeSeconds) {
                    ForEach(NotificationLeadTimeOption.allCases) { option in
                        Text(option.title)
                            .tag(option.seconds)
                    }
                }
                .disabled(episodeNotificationsEnabled == false)
                .onChange(of: leadTimeSeconds) { _, _ in
                    refreshNotifications(requestAuthorizationIfNeeded: false)
                }

                Button {
                    refreshNotifications(requestAuthorizationIfNeeded: true)
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh Scheduled Reminders", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }

            Section("Status") {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Cinue schedules reminders locally on this device from your imported or refreshed episode data. No account or server is used.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Notifications")
    }

    private func refreshNotifications(requestAuthorizationIfNeeded: Bool) {
        isRefreshing = true
        statusMessage = "Updating episode reminders."
        Task {
            let summary = await environment.notificationService.refreshUpcomingEpisodeNotifications(
                isEnabled: episodeNotificationsEnabled,
                leadTime: leadTimeSeconds,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
            statusMessage = summary.message
            isRefreshing = false
        }
    }
}

private enum NotificationLeadTimeOption: CaseIterable, Identifiable {
    case atRelease
    case oneHour
    case oneDay

    var id: Double { seconds }

    var title: String {
        switch self {
        case .atRelease:
            return "At release time"
        case .oneHour:
            return "1 hour before"
        case .oneDay:
            return "1 day before"
        }
    }

    var seconds: Double {
        switch self {
        case .atRelease:
            return 0
        case .oneHour:
            return 60 * 60
        case .oneDay:
            return 60 * 60 * 24
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environment(AppEnvironment.preview())
    }
}
