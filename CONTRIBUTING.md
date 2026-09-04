# Contributing to Cinue

## Development setup

Branch from `main`, keep the change focused, and open a focused pull request. Build the project with Xcode 26.6 and validate it on the iPhone 17 Pro simulator running iOS 26.5.

Run these commands from the repository root before opening a pull request:

```sh
xcodebuild test -workspace Cinue.xcworkspace -scheme Cinue -testPlan Cinue \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:CinueFeatureTests \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -workspace Cinue.xcworkspace -scheme Cinue \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO

git diff --check
git status --short
```

## Tests

Add Swift Testing coverage for model and service changes. Add XCTest UI coverage for user journeys that cross the app boundary. Keep tests deterministic and use synthetic fixtures rather than real viewing data.

## Privacy and content

Do not submit credentials, real viewing exports, or third-party copyrighted media. Use synthetic examples and metadata that you are allowed to share.

## Pull requests and commits

Describe the user-facing change, its tests, and any compatibility impact. Use a conventional commit-style squash title, such as `feat: add list sorting` or `fix: preserve backup preferences`.
