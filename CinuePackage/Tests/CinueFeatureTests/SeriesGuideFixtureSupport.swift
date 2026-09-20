import Foundation
import Testing

enum SeriesGuideFixture: String {
    case shows = "synthetic-shows"
    case movies = "synthetic-movies"
    case lists = "synthetic-lists"
}

func seriesGuideFixtureData(_ fixture: SeriesGuideFixture) throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: fixture.rawValue,
            withExtension: "json",
            subdirectory: "Fixtures/SeriesGuide"
        )
    )
    return try Data(contentsOf: url, options: [.mappedIfSafe])
}
