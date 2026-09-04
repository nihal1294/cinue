import SwiftUI
import CinueFeature

@main
struct CinueApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    await environment.prepareForAppOpen()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }

                    Task {
                        await environment.prepareForAppOpen()
                    }
                }
        }
    }
}
