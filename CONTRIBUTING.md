# Contributing to Cinue

## Development setup

Branch from `main`, keep the change focused, and open a focused pull request. Build the project with Xcode 26.6 and validate it on the iPhone 17 Pro simulator running iOS 26.5.

Run these commands from the repository root before opening a pull request:

```sh
xcodebuild test -workspace Cinue.xcworkspace -scheme Cinue -testPlan Cinue \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:CinueFeatureTests \
  CODE_SIGNING_ALLOWED=NO

git diff --check
git status --short
```

## Tests

Add Swift Testing coverage for model and service changes. Add XCTest UI coverage for user journeys that cross the app boundary. Keep tests deterministic and use synthetic fixtures rather than real viewing data.

## Privacy and content

Do not submit credentials, real viewing exports, or third-party copyrighted media. Use synthetic examples and metadata that you are allowed to share.

## Pull requests and commits

Describe the user-facing change, its tests, and any compatibility impact.

## Source releases

Before preparing a source release, choose a verified commit on `main` and confirm its required checks pass. Align the release version with the app's marketing version when one is set. In GitHub's release form, select that commit and use **Generate release notes**; review the notes and the source archive's installation instructions and documented limitations. Create the tag and publish the release as separate deliberate steps after review. Releases provide source code and do not promise a universally installable IPA.

### Simulator packages

The manually triggered **Simulator package** workflow builds a Release app for Apple Silicon iOS Simulator and produces a ZIP, SHA-256 checksum, and package information. Download its Actions artifact, verify the checksum, and install the extracted app on a clean compatible simulator before attaching the package files to a GitHub Release. Confirm the source revision matches the intended release and record the runtime used for validation in the release notes. The declared minimum OS is not a tested compatibility matrix.

The package must launch without a provider credential, offer the optional sample library on an empty installation, and retain normal library data after relaunch. Publishing a package does not provide a physical-device installer; keep the Simulator and free Personal Team instructions distinct. Release artifacts must come from a clean reviewed revision.
