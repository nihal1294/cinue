import Testing
@testable import CinueFeature

struct ProviderCredentialSummaryTests {
    @Test
    func savedCredentialIsConfiguredAndMaskedWithoutRevealingRawValue() {
        let summary = ProviderCredentialSummary(value: "1234567890abcdef")

        #expect(summary.isConfigured)
        #expect(summary.statusText == "Configured")
        #expect(summary.maskedValue == "********cdef")
        #expect(summary.maskedValue.contains("1234567890") == false)
    }

    @Test
    func emptyCredentialShowsNotConfiguredState() {
        let summary = ProviderCredentialSummary(value: "   ")

        #expect(summary.isConfigured == false)
        #expect(summary.statusText == "Not Configured")
        #expect(summary.maskedValue == "No saved credential")
    }
}
