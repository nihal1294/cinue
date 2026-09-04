import Testing
@testable import CinueFeature

struct ProviderSettingsConfigurationTests {
    @Test
    func tmdbIsTheOnlyActiveMetadataProviderForPersonalBuild() {
        #expect(ProviderSettingsConfiguration.activeProviders == [.tmdb])
        #expect(ProviderSettingsConfiguration.showsTheTVDBSetup == false)
    }
}
