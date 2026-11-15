---
title: Install and run
---

## Choose how to try Cinue

| Your goal | Start here |
| --- | --- |
| See the app on any device | [Watch the short walkthroughs](https://nihal1294.github.io/cinue/#see-cinue-in-action) |
| Try the app on an Apple Silicon Mac | [Install a Simulator download](#try-a-simulator-download), when one is available in Releases |
| Build the app yourself or use your own iPhone/iPad | [Build from source](#build-from-source) |

Neither the Simulator route nor a personal-device build requires a paid Apple Developer Program membership. A Simulator download still needs a Mac with Xcode and an installed iOS Simulator runtime. A physical device requires your own Apple Account and signing setup.

## Requirements

- A Mac with Xcode 26.6 or newer, opened once to install its required components
- An installed iOS Simulator runtime, or an iPhone/iPad running iOS 17.0 or later
- No external Swift packages

## Try a Simulator download

Open [Cinue Releases](https://github.com/nihal1294/cinue/releases) and look for **Cinue-iOS-Simulator-arm64.zip**. Packages are provided only when attached to a release; if the release has no Simulator package, use the source instructions below.

This package is for an **Apple Silicon Mac running iOS Simulator**. It is not an iPhone installer or a native Mac application. Check the accompanying package information for the app version, build SDK, and declared minimum runtime.

1. Download the ZIP and its `.sha256` checksum file from the same release.
2. In Terminal, from the download folder, verify the archive:

   ```sh
   shasum -a 256 -c Cinue-iOS-Simulator-arm64.zip.sha256
   ```

3. Unzip the archive to obtain **Cinue.app**.
4. Open an iPhone or iPad simulator in Xcode's Simulator or Device Hub. Start only the simulator you want to use for Cinue.
5. From the folder containing `Cinue.app`, install and launch it:

   ```sh
   xcrun simctl install booted Cinue.app
   xcrun simctl launch booted com.nihal.Cinue
   ```

If more than one simulator is running, use the chosen device's identifier in place of `booted`; `xcrun simctl list devices booted` lists them. You can also launch Cinue from the simulator's Home Screen after installation.

No project build or device-signing setup is required for this download. [Explore the sample library](#try-a-sample-library) to get started without a TMDB key.

## Build from source

Clone the source to build for Simulator, make changes, or install on your own device. There is no prebuilt iPhone/iPad installer or TestFlight download.

### Clone and open

In Terminal, from the directory where you keep projects:

```sh
git clone https://github.com/nihal1294/cinue.git
cd cinue
open Cinue.xcworkspace
```

Open the workspace rather than `CinuePackage` alone so the app and test targets are available together. Then choose one of the following paths.

### Run in Simulator

1. Select the **Cinue** scheme in Xcode's toolbar.
2. Select an available iPhone or iPad simulator as the run destination, not **Any iOS Device** or a physical device. If no simulator is available, install an iOS runtime in **Xcode > Settings > Components** and create/select a simulator in the device picker.
3. Choose **Product > Run** or press **Command-R**. Xcode builds Cinue and opens it in Simulator.

A paid Apple Developer membership and a device provisioning profile are not needed for Simulator. The library starts empty; you can try fictional sample items, import a backup, or configure TMDB and add titles through Discover.

### Run on your iPhone or iPad

1. Connect and unlock your device, accept **Trust This Computer** if prompted, and select it as Xcode's run destination. Allow Xcode to finish pairing and preparing the device.
2. In **Xcode > Settings > Apple Accounts** (called **Accounts** in some versions), sign in with your own Apple Account.
3. Select the **Cinue** project in the navigator, then the **Cinue** app target and **Signing & Capabilities**. Enable **Automatically manage signing** and choose your **Team**. A free account appears as a **Personal Team**.
4. Change `PRODUCT_BUNDLE_IDENTIFIER` in `Config/Shared.xcconfig` from `com.nihal.Cinue` to an identifier unique to you, such as `com.yourname.Cinue`. Keep the same identifier for later installs of your copy; changing it creates a separate app and does not move its library.
5. If requested, enable **Settings > Privacy & Security > Developer Mode** on the device, restart it, and confirm the prompt after unlocking. The option may only appear after pairing with Xcode. See [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
6. Choose **Product > Run** or press **Command-R**. If the device reports an untrusted developer, follow its prompt to trust your own developer identity under **Settings > General > VPN & Device Management**, then run again.

With a free Personal Team, provisioning expires after seven days and you must rebuild and reinstall through Xcode. This is personal-device testing, not a way to distribute a universally installable app. See [Apple's account and provisioning limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

Export a Cinue backup before deleting the app, changing its bundle identifier, or moving to another device. See the [User Guide](https://github.com/nihal1294/cinue/blob/main/docs/USER_GUIDE.md#import-export-and-backup).

## Try a sample library

On a fresh installation, open **Now** or **Library** and choose **Try a sample library**. Cinue adds fictional shows, movies, episodes, and a list to the local library so you can explore watch progress, favorites, lists, and Insights without a TMDB credential.

The action is available only when the library has no items, episode state, lists, or list entries. Cinue checks again before adding samples and declines if other data or an import is present. It does not change provider credentials or preferences.

These are ordinary local library items, not a separate account or temporary session. You can edit or remove them with the normal controls, and they are included in your backups. Sample titles have no TMDB provider IDs or remote artwork; they do not enable live discovery. If you already have a library, your existing data is kept and sample items are not added.

## Optional: enable TMDB discovery

In Cinue, open **Settings** > **Provider Keys** and enter your own TMDB v3 API key or v4 read access token to enable discovery and metadata refresh. See [Privacy](https://github.com/nihal1294/cinue/blob/main/docs/USER_GUIDE.md#attribution-and-privacy) for credential storage and artwork requests.

Without a credential, you can still try the sample library or import a supported backup and use local tracking, lists, and statistics. The screenshots show a populated library; the fictional sample is a separate collection.

## Build and installation troubleshooting

- **No runnable destination or missing iOS runtime:** install the platform/runtime Xcode requests, then select a specific simulator or connected device. A phone running a newer OS may require a newer Xcode version.
- **Signing requires a development team:** select your own Team for the Cinue app target. If you only want Simulator, check that the destination is actually a simulator.
- **Bundle identifier cannot be registered or provisioning fails:** use a unique identifier, keep automatic signing enabled, and confirm that your Apple Account is signed in. Xcode needs network access to create or refresh device provisioning.
- **The app no longer opens on a Personal Team device:** rebuild and run from Xcode to renew provisioning. Do not delete the app as the first troubleshooting step; export a backup before any deletion.
- **Discover is unavailable or the library is empty:** add your own TMDB credential for discovery, or import a supported backup. An empty library on first launch is expected.
