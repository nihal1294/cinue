import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            Section("Build") {
                LabeledContent("Mode", value: "Local Only")
                LabeledContent("Persistence", value: persistenceLabel)
                LabeledContent("CloudKit", value: environment.persistence.mode.isCloudKitEnabled ? "Active" : "Off")
            }

            Section("Storage") {
                Text("Diagnostics avoid watch history, notes, search terms, and raw provider payloads.")
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Diagnostics")
    }

    private var persistenceLabel: String {
        switch environment.persistence.mode {
        case .localOnly:
            "Local Core Data"
        case .cloudKit:
            "Core Data + CloudKit"
        case .inMemory:
            "In Memory"
        }
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environment(AppEnvironment.preview())
    }
}
