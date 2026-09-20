# Cinue User Guide

Cinue keeps your show and movie library on your iPhone or iPad. It works without an account and stores watch state locally.

## Now

The **Now** tab organizes released episodes into **Up Next**, **Recently Watched**, and **Recently Aired**, while **Upcoming** contains episodes with future air dates. Tap a summary tile or section to switch the view. Use the watch action on an eligible episode to mark it watched; the episode then moves into your history and your progress updates.

Open a show or episode for more actions. Episode details let you mark an episode watched or unwatched, watch it again, mark watched up to an episode, skip or unskip it, add or remove it from your collection, and edit a private rating or note.

## Library

The **Library** tab shows your local shows and movies. Use the filter and sort controls to narrow the view, including shows, movies, favorites, and watched items. From an item, you can mark it watched, add or remove it from favorites, hide it from the library, manage its list membership, or remove it from the library.

Hiding an item removes it from the normal library view without deleting its data. Removing an item deletes that item and its associated local watch data; export a backup first if you may want to restore it later.

## Discover

The **Discover** tab searches and browses titles from TMDB. Add a search result to the library, or add a movie to the watchlist from its detail screen.

TMDB discovery and metadata refresh need your own credential. Open **Settings** > **Provider Keys**, then save either a TMDB v3 API key or a TMDB v4 read access token. The credential stays in this device's Keychain and is not included in Cinue backups. Artwork for a library item with an approved TMDB artwork URL, including an imported or retained URL, may load separately from the approved `image.tmdb.org` image service without a saved credential. Your watch history, lists, ratings, notes, and backups remain local. TMDB is the active provider; TheTVDB and TVmaze are not active providers in Cinue.

## Lists

The **Lists** tab contains the movie watchlist and your custom lists. Create a list, give it a name, then manage membership from a library item or the list itself. You can rename a list, change its ordering, remove an item from a list, or delete a list. Deleting a list removes its memberships but does not remove the underlying show or movie from your library.

## Insights

Open **Settings** > **Insights** to review local totals and progress. The show section reports your total shows, shows with released next episodes, continuing shows, and finished shows. The episode and movie sections show watched counts and estimated watch time when runtime information is available. Movie metrics also distinguish watchlist and collection totals and their estimated runtime.

## Settings

### Display

Choose System, Light, or Dark appearance in **Display**. Turn on **Hide Episode Spoilers** to hide titles and summaries for unwatched episodes. Turn on **Use Exact Dates** to show full local release dates.

### Notifications

In **Notifications**, enable local reminders for upcoming unwatched episodes and choose a reminder time at release, one hour before, or one day before. Cinue schedules these reminders on the device; no account or server is used.

### Provider Keys

In **Provider Keys**, save, replace, or remove your TMDB credential and choose a preferred metadata language. The key is user supplied, stored in a ThisDeviceOnly Keychain item, and excluded from Cinue backups.

### Import, export, and backup

Use **Import and Export** to create a Cinue JSON backup or import a Cinue or supported SeriesGuide JSON backup from Files. Cinue backups include supported library data and preferences, but never provider credentials. The **Backup and Sync** screen documents the current local-only mode: automatic iCloud sync is not active.

For SeriesGuide exports stored in separate files, import them in this order:

1. Shows
2. Movies
3. Lists

This lets list entries resolve to the shows and movies already present in your Cinue library.

### Clearing data

Cinue does not currently provide one Settings action that clears all local data. Remove individual items or lists from their own screens when you want to delete them. If you need to reset the local library, export any backup you want to keep and remove the app from the device. Remove the TMDB credential in **Provider Keys** separately if you no longer want it stored in the Keychain. Importing a file changes the local library, so keep a current Cinue backup before an import, a migration, or a reset.

## Attribution and privacy

Open **Settings** > **Attribution** to see the TMDB notice and SeriesGuide import-compatibility information. Cinue has no account, analytics, telemetry, or backend. Watch history, preferences, and backups remain local unless you export a file yourself.
