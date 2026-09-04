import Testing
@testable import CinueFeature

struct CinueTransientFeedbackTests {
    @Test
    func productionDurationsStayBrief() {
        #expect(CinueTransientFeedback.resolvedDisplayDuration(arguments: []) == 2.8)
        #expect(CinueTransientFeedback.resolvedActionableDisplayDuration(arguments: []) == 6.0)
    }

    @Test
    func seededUITestsKeepFeedbackVisibleWhileXCTestWaitsForIdle() {
        let arguments = ["Cinue", "--cinue-ui-test-seed"]

        #expect(CinueTransientFeedback.resolvedDisplayDuration(arguments: arguments) == 12.0)
        #expect(CinueTransientFeedback.resolvedActionableDisplayDuration(arguments: arguments) == 12.0)
    }
}
