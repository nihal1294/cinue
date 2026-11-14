# Cinue

Cinue is a local-first TV show and movie tracker for iPhone and iPad, built with SwiftUI and Core Data.

It provides a private on-device library, episode progress, lists, statistics, local backup and restore, SeriesGuide-compatible JSON import, and optional TMDB-powered discovery and metadata refresh.

> Cinue is an independent open-source project. It is not affiliated with or endorsed by SeriesGuide. SeriesGuide is referenced solely to describe backup-format compatibility.

## Highlights

- Keep a private on-device library of shows and movies, with episode progress, favorites, watchlist, notes, ratings, and custom lists.
- Use the Now tab to follow up next, recently watched, recently aired, and upcoming episodes.
- Discover titles and refresh metadata with an optional user-supplied TMDB credential.
- Export and import Cinue JSON backups, or migrate supported SeriesGuide JSON backups.
- Keep data local: Cinue has no account, analytics, telemetry, or backend.

## Screenshots

![iPhone Now, light appearance](docs/media/screenshots/iphone-now-light.png)

| iPhone Library, dark appearance | iPhone detail, dark appearance |
| --- | --- |
| ![iPhone Library, dark appearance](docs/media/screenshots/iphone-library-dark.png) | ![iPhone detail, dark appearance](docs/media/screenshots/iphone-detail-dark.png) |

![iPad Library, dark appearance](docs/media/screenshots/ipad-library-dark.png)

## Demo

| Now | Library | Discover and detail |
| --- | --- | --- |
| [![Now walkthrough](docs/media/screenshots/iphone-now-light.png)](docs/media/clips/cinue-now.mp4) | [![Library walkthrough](docs/media/screenshots/iphone-library-dark.png)](docs/media/clips/cinue-library.mp4) | [![Discover and detail walkthrough](docs/media/screenshots/iphone-detail-dark.png)](docs/media/clips/cinue-discover-detail.mp4) |

## Getting Started

Cinue is distributed as source code. To try it, clone the repository and open the workspace in Xcode:

```sh
git clone https://github.com/nihal1294/cinue.git
cd cinue
open Cinue.xcworkspace
```

Select the **Cinue** scheme and an iPhone or iPad simulator, then choose **Product > Run**. See [Install and run](docs/installation.md) for requirements, device signing, optional TMDB setup, and troubleshooting.

## Importing from SeriesGuide

Cinue can import supported JSON backups produced by SeriesGuide. In **Settings** > **Import and Export**, choose a JSON file from Files. For a SeriesGuide export split across files, import shows first, then movies, then lists so list items can resolve to their matching library entries.

Importing changes the local library. Export a Cinue backup before migrating or replacing data.

## Privacy

Cinue stores watch history, lists, preferences, and imported data locally with Core Data. There is no account, analytics, telemetry, or backend. A saved TMDB credential authorizes discovery and metadata API requests. Remote artwork is fetched separately from the approved `image.tmdb.org` image service when a library item has an approved artwork URL, including an imported or retained URL, and may load without a saved credential. Credentials are user supplied, stored in the device Keychain, and excluded from backups. Your watch history, lists, ratings, notes, and backups remain local.

Automatic iCloud sync is not active. Use the manual JSON export and import flow to move data between devices or keep a copy outside the app.

## User Guide

See the [User Guide](docs/USER_GUIDE.md) for everyday use.

## Testing

Run the feature test suite from the repository root:

```sh
xcodebuild test -workspace Cinue.xcworkspace -scheme Cinue -testPlan Cinue \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:CinueFeatureTests \
  CODE_SIGNING_ALLOWED=NO
```

GitHub Actions runs repository checks, an iOS build, unit tests, UI tests, and static analysis for pull requests and updates to `main`.

## Project Status

Cinue has no tagged releases yet. The project supports local Core Data storage, manual JSON backup and restore, and optional TMDB integration. iCloud auto-sync is not currently active.

## Attribution

This product uses the TMDB API but is not endorsed or certified by TMDB. The app displays TMDB attribution, and the complete provenance and attribution record is in [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Contributing

Read [Contributing](CONTRIBUTING.md) for development, testing, and pull-request expectations.

## Security

Read the [Security Policy](SECURITY.md) to report a vulnerability privately.

## License

Cinue is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for copyright notices.
