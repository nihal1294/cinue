import SwiftUI

enum CinueTransientFeedback {
    static let displayDuration = resolvedDisplayDuration(arguments: ProcessInfo.processInfo.arguments)
    static let actionableDisplayDuration = resolvedActionableDisplayDuration(arguments: ProcessInfo.processInfo.arguments)

    static func resolvedDisplayDuration(arguments: [String]) -> TimeInterval {
        arguments.contains("--cinue-ui-test-seed") ? 12.0 : 2.8
    }

    static func resolvedActionableDisplayDuration(arguments: [String]) -> TimeInterval {
        arguments.contains("--cinue-ui-test-seed") ? 12.0 : 6.0
    }
}

private struct CinueAutoDismissFeedbackModifier: ViewModifier {
    @Binding var message: String?

    let delay: TimeInterval

    func body(content: Content) -> some View {
        content
            .task(id: message) {
                guard let currentMessage = message, currentMessage.isEmpty == false else {
                    return
                }

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard Task.isCancelled == false else {
                    return
                }

                await MainActor.run {
                    guard message == currentMessage else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        message = nil
                    }
                }
            }
    }
}

extension View {
    func cinueAutoDismissFeedback(
        _ message: Binding<String?>,
        after delay: TimeInterval = CinueTransientFeedback.displayDuration
    ) -> some View {
        modifier(CinueAutoDismissFeedbackModifier(message: message, delay: delay))
    }
}
