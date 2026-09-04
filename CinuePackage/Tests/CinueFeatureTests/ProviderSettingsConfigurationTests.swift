import Testing
@testable import CinueFeature

struct ProviderSettingsConfigurationTests {
    @Test
    func tmdbIsTheOnlyActiveMetadataProvider() {
        #expect(ProviderSettingsConfiguration.activeProviders == [.tmdb])
        #expect(ProviderSettingsConfiguration.showsTheTVDBSetup == false)
    }
}
