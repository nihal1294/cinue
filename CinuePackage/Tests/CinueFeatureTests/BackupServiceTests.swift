import CoreData
import Foundation
import Testing
@testable import CinueFeature

@MainActor
struct BackupServiceTests {
    @Test
    func importBackupRejectsDataAboveByteLimitBeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: BackupImportPolicy(
                maximumFileBytes: 32,
                maximumTopLevelRecords: 10,
                maximumNestedEpisodes: 10,
                maximumAggregateRecords: 10,
                maximumStringUTF8Bytes: 100,
                maximumJSONNestingDepth: 4
            )
        )

        do {
            _ = try service.importBackup(data: Data(repeating: 0, count: 33))
            Issue.record("Expected the import to reject data above the byte limit.")
        } catch let error as BackupImportError {
            #expect(error == .fileTooLarge(actualBytes: 33, maximumBytes: 32))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupFileRejectsFileAboveByteLimitBeforeReading() async throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: BackupImportPolicy(
                maximumFileBytes: 32,
                maximumTopLevelRecords: 10,
                maximumNestedEpisodes: 10,
                maximumAggregateRecords: 10,
                maximumStringUTF8Bytes: 100,
                maximumJSONNestingDepth: 4
            )
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinue-backup-byte-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 0, count: 33).write(to: fileURL, options: .atomic)

        do {
            _ = try await service.importBackupFile(at: fileURL)
            Issue.record("Expected the file import to reject a file above the byte limit.")
        } catch let error as BackupImportError {
            #expect(error == .fileTooLarge(actualBytes: 33, maximumBytes: 32))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupFileRejectsNonRegularFileBeforeMutation() async throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinue-backup-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await service.importBackupFile(at: directory)
            Issue.record("Expected a directory to be rejected as a non-regular backup file.")
        } catch let error as BackupImportError {
            #expect(error == .invalidPayload)
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupFileRejectsSymlinkBeforeMutation() async throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinue-backup-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let targetURL = directory.appendingPathComponent("backup.json")
        try Data(#"[{ "tmdb_id": 1, "title": "Target", "watched": true }]"#.utf8)
            .write(to: targetURL, options: .atomic)
        let symlinkURL = directory.appendingPathComponent("backup-link.json")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        do {
            _ = try await service.importBackupFile(at: symlinkURL)
            Issue.record("Expected a symbolic link to be rejected as a backup file.")
        } catch {
            // `O_NOFOLLOW` reports the platform-specific POSIX error after the regular-file preflight.
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupRejectsTopLevelRecordCountAboveLimitBeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: testImportPolicy(maximumTopLevelRecords: 1)
        )
        let json = """
        [
          { "tmdb_id": 1, "title": "First" },
          { "tmdb_id": 2, "title": "Second" }
        ]
        """

        do {
            _ = try service.importBackup(data: Data(json.utf8))
            Issue.record("Expected the import to reject too many top-level records.")
        } catch let error as BackupImportError {
            #expect(error == .topLevelRecordLimitExceeded(actual: 2, maximum: 1))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupRejectsNestedEpisodeCountAboveLimitBeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: testImportPolicy(maximumNestedEpisodes: 1)
        )
        let json = """
        [
          {
            "tmdb_id": 1,
            "title": "Show",
            "seasons": [
              { "season": 1, "episodes": [{ "episode": 1 }, { "episode": 2 }] }
            ]
          }
        ]
        """

        do {
            _ = try service.importBackup(data: Data(json.utf8))
            Issue.record("Expected the import to reject too many nested episodes.")
        } catch let error as BackupImportError {
            #expect(error == .nestedEpisodeLimitExceeded(actual: 2, maximum: 1))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupRejectsAggregateRecordCountAboveLimitBeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: testImportPolicy(maximumAggregateRecords: 1)
        )
        let json = """
        [
          { "tmdb_id": 1, "title": "First" },
          { "tmdb_id": 2, "title": "Second" }
        ]
        """

        do {
            _ = try service.importBackup(data: Data(json.utf8))
            Issue.record("Expected the import to reject too many aggregate records.")
        } catch let error as BackupImportError {
            #expect(error == .aggregateRecordLimitExceeded(actual: 2, maximum: 1))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupRejectsUTF8StringAboveByteLimitBeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: testImportPolicy(maximumStringUTF8Bytes: 8)
        )
        let json = """
        [{ "tmdb_id": 1, "title": "123456789" }]
        """

        do {
            _ = try service.importBackup(data: Data(json.utf8))
            Issue.record("Expected the import to reject an oversized UTF-8 string.")
        } catch let error as BackupImportError {
            #expect(error == .stringLimitExceeded(actualUTF8Bytes: 9, maximumUTF8Bytes: 8))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupRejectsJSONNestingAboveLimitBeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            importPolicy: testImportPolicy(maximumJSONNestingDepth: 3)
        )
        let json = """
        [{ "tmdb_id": 1, "unknown": { "nested": {} } }]
        """

        do {
            _ = try service.importBackup(data: Data(json.utf8))
            Issue.record("Expected the import to reject JSON nested beyond the policy limit.")
        } catch let error as BackupImportError {
            #expect(error == .nestingLimitExceeded(actualDepth: 4, maximumDepth: 3))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupMapsParsedNonDocumentJSONToInvalidPayload() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)

        do {
            _ = try service.importBackup(data: Data("true".utf8))
            Issue.record("Expected a parsed non-document JSON fragment to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .invalidPayload)
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importBackupRejectsEveryInt32BackedFieldOutsideRange() throws {
        let outOfRange = Int(Int32.max) + 1
        let documents: [(BackupIntegerField, CinueBackupDocument)] = [
            (
                .trackedItemWatchCount,
                CinueBackupDocument(
                    exportedAt: fixedDate(),
                    trackedItems: [makeCinueTrackedItem(watchCount: outOfRange)]
                )
            ),
            (
                .episodeSeasonNumber,
                CinueBackupDocument(
                    exportedAt: fixedDate(),
                    trackedItems: [],
                    episodeStates: [makeCinueEpisodeState(seasonNumber: outOfRange)]
                )
            ),
            (
                .episodeNumber,
                CinueBackupDocument(
                    exportedAt: fixedDate(),
                    trackedItems: [],
                    episodeStates: [makeCinueEpisodeState(episodeNumber: outOfRange)]
                )
            ),
            (
                .episodeWatchCount,
                CinueBackupDocument(
                    exportedAt: fixedDate(),
                    trackedItems: [],
                    episodeStates: [makeCinueEpisodeState(watchCount: outOfRange)]
                )
            ),
            (
                .userListSortOrder,
                CinueBackupDocument(
                    exportedAt: fixedDate(),
                    trackedItems: [],
                    lists: [
                        CinueBackupList(
                            localID: "list-1",
                            name: "List",
                            sortOrder: outOfRange,
                            createdAt: fixedDate(),
                            updatedAt: fixedDate()
                        )
                    ]
                )
            ),
            (
                .userListItemSortOrder,
                CinueBackupDocument(
                    exportedAt: fixedDate(),
                    trackedItems: [],
                    listItems: [
                        CinueBackupListItem(
                            localID: "list-item-1",
                            listLocalID: "list-1",
                            itemLocalID: nil,
                            externalID: "external-1",
                            kindRaw: "movie",
                            tvdbID: nil,
                            tmdbID: 1,
                            sortOrder: outOfRange,
                            createdAt: fixedDate(),
                            updatedAt: fixedDate()
                        )
                    ]
                )
            )
        ]

        for (field, document) in documents {
            let controller = PersistenceController(inMemory: true)
            let service = BackupService(persistence: controller, now: fixedDate)

            do {
                _ = try service.importCinueBackup(data: backupEncoder.encode(document))
                Issue.record("Expected \(field.rawValue) outside Int32 range to be rejected.")
            } catch let error as BackupImportError {
                #expect(error == .integerOutOfRange(field: field, value: outOfRange))
            }

            try expectImportableEntityCountsAreZero(in: controller)
        }
    }

    @Test
    func importCinueBackupRejectsTrackedUserRatingOutsideInt16BeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let outOfRange = Int(Int16.max) + 1
        let document = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [makeCinueTrackedItem(watchCount: 1, userRating: outOfRange)]
        )

        do {
            _ = try service.importCinueBackup(data: backupEncoder.encode(document))
            Issue.record("Expected an out-of-range tracked-item user rating to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .integerOutOfRange(field: .trackedItemUserRating, value: outOfRange))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importCinueBackupRejectsEpisodeUserRatingOutsideInt16BeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let outOfRange = Int(Int16.max) + 1
        let document = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [],
            episodeStates: [makeCinueEpisodeState(userRating: outOfRange)]
        )

        do {
            _ = try service.importCinueBackup(data: backupEncoder.encode(document))
            Issue.record("Expected an out-of-range episode user rating to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .integerOutOfRange(field: .episodeUserRating, value: outOfRange))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importSeriesGuideShowsRejectsUserRatingOutsideInt16BeforeMutation() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let outOfRange = Int(Int16.max) + 1
        let json = """
        [{ "tmdb_id": 1, "title": "Rating", "rating_user": \(outOfRange) }]
        """

        do {
            _ = try service.importSeriesGuideShows(data: Data(json.utf8))
            Issue.record("Expected an out-of-range SeriesGuide user rating to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .integerOutOfRange(field: .trackedItemUserRating, value: outOfRange))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func importSeriesGuideShowsRejectsOverflowingTotalEpisodePlaysWithoutPartialState() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let firstPlayCount = Int.max
        let json = """
        [
          {
            "tmdb_id": 1,
            "title": "Overflow Show",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "episode": 1, "plays": \(firstPlayCount) },
                  { "episode": 2, "plays": 1 }
                ]
              }
            ]
          }
        ]
        """

        do {
            _ = try service.importSeriesGuideShows(data: Data(json.utf8))
            Issue.record("Expected total episode plays to reject integer overflow.")
        } catch let error as BackupImportError {
            #expect(error == .integerOverflow(field: .totalEpisodePlays))
        }

        try expectImportableEntityCountsAreZero(in: controller)
    }

    @Test
    func failedCinueBackupSaveRollsBackDataAndLeavesPreferencesUnchanged() throws {
        let controller = PersistenceController(inMemory: true)
        let defaults = try makeTestDefaults()
        defer { reset(defaults: defaults) }
        setOriginalPreferences(in: defaults)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            userDefaults: defaults,
            contextSave: { _ in throw ExpectedSaveFailure.failed }
        )
        let document = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [makeCinueTrackedItem(watchCount: 1)],
            preferences: importedPreferences()
        )

        do {
            _ = try service.importCinueBackup(data: backupEncoder.encode(document))
            Issue.record("Expected the injected save failure to be thrown.")
        } catch ExpectedSaveFailure.failed {
        }

        try expectImportableEntityCountsAreZero(in: controller)
        expectOriginalPreferences(in: defaults)
    }

    @Test
    func successfulCinueBackupSaveAppliesPreferences() throws {
        let controller = PersistenceController(inMemory: true)
        let defaults = try makeTestDefaults()
        defer { reset(defaults: defaults) }
        setOriginalPreferences(in: defaults)
        let service = BackupService(
            persistence: controller,
            now: fixedDate,
            userDefaults: defaults
        )
        let document = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [makeCinueTrackedItem(watchCount: 1)],
            preferences: importedPreferences()
        )

        _ = try service.importCinueBackup(data: backupEncoder.encode(document))

        #expect(try trackedItemCount(in: controller) == 1)
        #expect(defaults.string(forKey: CinuePreferenceKeys.appearanceMode) == CinueAppearanceMode.dark.rawValue)
        #expect(defaults.bool(forKey: CinuePreferenceKeys.hideEpisodeSpoilers) == true)
        #expect(defaults.bool(forKey: CinuePreferenceKeys.useExactDates) == false)
        #expect(defaults.string(forKey: CinuePreferenceKeys.tmdbLanguageCode) == "en-US")
        #expect(defaults.bool(forKey: CinuePreferenceKeys.episodeNotificationsEnabled) == true)
        #expect(defaults.double(forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds) == 3600.0)
    }

    @Test
    func syntheticSeriesGuideFixturesImportIntoCoreData() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)

        _ = try service.importBackup(data: seriesGuideFixtureData(.shows))
        _ = try service.importBackup(data: seriesGuideFixtureData(.movies))
        _ = try service.importBackup(data: seriesGuideFixtureData(.lists))

        #expect(try entityCount(in: controller, entityName: "TrackedItem") == 4)
        #expect(try entityCount(in: controller, entityName: "EpisodeState") == 4)
        #expect(try entityCount(in: controller, entityName: "UserList") == 1)
        #expect(try entityCount(in: controller, entityName: "UserListItem") == 2)
        #expect(try entityCount(in: controller, entityName: "MetadataRecord") == 8)
    }

    @Test
    func reimportingSyntheticSeriesGuideFixturesUpdatesWithoutDuplicatingRecords() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)

        _ = try service.importBackup(data: seriesGuideFixtureData(.shows))
        _ = try service.importBackup(data: seriesGuideFixtureData(.movies))
        _ = try service.importBackup(data: seriesGuideFixtureData(.lists))
        let shows = try service.importBackup(data: seriesGuideFixtureData(.shows))
        let movies = try service.importBackup(data: seriesGuideFixtureData(.movies))
        let lists = try service.importBackup(data: seriesGuideFixtureData(.lists))

        #expect(shows.updatedItems == 6)
        #expect(movies.updatedItems == 2)
        #expect(lists.updatedItems == 3)

        #expect(try entityCount(in: controller, entityName: "TrackedItem") == 4)
        #expect(try entityCount(in: controller, entityName: "EpisodeState") == 4)
        #expect(try entityCount(in: controller, entityName: "UserList") == 1)
        #expect(try entityCount(in: controller, entityName: "UserListItem") == 2)
        #expect(try entityCount(in: controller, entityName: "MetadataRecord") == 8)
    }

    @Test
    func exportCinueBackupIncludesTrackedItems() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        try insertTrackedItem(
            into: controller,
            localID: "local-show-1",
            kindRaw: "show",
            title: "Example Show",
            tvdbID: 332331,
            tmdbID: 68421,
            imdbID: "tt2261227",
            statusRaw: "watching",
            watchCount: 2,
            isFavorite: true
        )

        let data = try service.exportCinueBackup()
        let document = try backupDecoder.decode(CinueBackupDocument.self, from: data)

        #expect(document.app == "Cinue")
        #expect(document.schemaVersion == 1)
        #expect(document.exportedAt == fixedDate())
        #expect(document.trackedItems.count == 1)
        #expect(document.trackedItems.first?.title == "Example Show")
        #expect(document.trackedItems.first?.tvdbID == 332331)
        #expect(document.trackedItems.first?.tmdbID == 68421)
        #expect(document.episodeStates.isEmpty)
        #expect(document.lists.isEmpty)
        #expect(document.listItems.isEmpty)
    }

    @Test
    func importCinueBackupCreatesTrackedItems() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let document = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [
                CinueBackupTrackedItem(
                    localID: "local-movie-1",
                    kindRaw: "movie",
                    title: "Example Movie",
                    sortTitle: "example movie",
                    tvdbID: nil,
                    tmdbID: 19913,
                    imdbID: "tt1022603",
                    statusRaw: "watched",
                    watchCount: 1,
                    watchedAt: fixedDate(),
                    isCollected: false,
                    isFavorite: false,
                    isHidden: false,
                    userRating: 8,
                    notes: "Imported note",
                    createdAt: fixedDate(),
                    updatedAt: fixedDate()
                )
            ]
        )

        let summary = try service.importCinueBackup(data: backupEncoder.encode(document))

        #expect(summary.importedItems == 1)
        #expect(try trackedItemCount(in: controller) == 1)

        let item = try fetchTrackedItem(in: controller, localID: "local-movie-1")
        #expect(item.value(forKey: "title") as? String == "Example Movie")
        #expect(item.value(forKey: "statusRaw") as? String == "watched")
        #expect(item.value(forKey: "notes") as? String == "Imported note")
    }

    @Test
    func providerMatchedImportPreservesCanonicalLocalIDForExistingAndImportedRelationships() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let canonicalShowID = "canonical-show"
        let canonicalListID = "canonical-list"
        let initialBackup = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [
                canonicalTrackedItem(
                    localID: canonicalShowID,
                    kindRaw: "show",
                    title: "Original Show",
                    tmdbID: 42
                )
            ],
            episodeStates: [
                canonicalEpisodeState(
                    localID: "canonical-episode",
                    showLocalID: canonicalShowID
                )
            ],
            lists: [
                canonicalUserList(localID: canonicalListID, name: "Existing List")
            ],
            listItems: [
                canonicalUserListItem(
                    localID: "canonical-list-item",
                    listLocalID: canonicalListID,
                    itemLocalID: canonicalShowID
                )
            ]
        )
        _ = try service.importCinueBackup(data: backupEncoder.encode(initialBackup))

        let conflictingLocalID = "incoming-show"
        let importedBackup = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [
                canonicalTrackedItem(
                    localID: conflictingLocalID,
                    kindRaw: "show",
                    title: "Imported Show",
                    tmdbID: 42
                )
            ],
            episodeStates: [
                canonicalEpisodeState(
                    localID: "imported-episode",
                    showLocalID: conflictingLocalID
                )
            ],
            lists: [
                canonicalUserList(localID: "imported-list", name: "Imported List")
            ],
            listItems: [
                canonicalUserListItem(
                    localID: "imported-list-item",
                    listLocalID: "imported-list",
                    itemLocalID: conflictingLocalID
                )
            ]
        )

        _ = try service.importCinueBackup(data: backupEncoder.encode(importedBackup))

        #expect(try trackedItemCount(in: controller) == 1)
        let show = try fetchTrackedItem(in: controller, localID: canonicalShowID)
        #expect(show.value(forKey: "title") as? String == "Imported Show")

        let existingEpisode = try fetchObject(
            in: controller,
            entityName: "EpisodeState",
            localID: "canonical-episode"
        )
        let importedEpisode = try fetchObject(
            in: controller,
            entityName: "EpisodeState",
            localID: "imported-episode"
        )
        #expect(existingEpisode.value(forKey: "showLocalID") as? String == canonicalShowID)
        #expect(importedEpisode.value(forKey: "showLocalID") as? String == canonicalShowID)

        let existingListItem = try fetchObject(
            in: controller,
            entityName: "UserListItem",
            localID: "canonical-list-item"
        )
        let importedListItem = try fetchObject(
            in: controller,
            entityName: "UserListItem",
            localID: "imported-list-item"
        )
        #expect(existingListItem.value(forKey: "itemLocalID") as? String == canonicalShowID)
        #expect(importedListItem.value(forKey: "itemLocalID") as? String == canonicalShowID)
    }

    @Test
    func seriesGuideShowImportUsesExistingCanonicalLocalIDForEpisodesAndMetadata() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let canonicalShowID = "canonical-show"
        let initialBackup = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [
                canonicalTrackedItem(
                    localID: canonicalShowID,
                    kindRaw: "show",
                    title: "Existing Show",
                    tmdbID: 68421
                )
            ]
        )
        _ = try service.importCinueBackup(data: backupEncoder.encode(initialBackup))

        let seriesGuideJSON = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Imported Show",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "episode": 1, "title": "Pilot", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try service.importSeriesGuideShows(data: Data(seriesGuideJSON.utf8))

        #expect(try trackedItemCount(in: controller) == 1)
        let episode = try fetchObject(
            in: controller,
            entityName: "EpisodeState",
            localID: "seriesguide:episode:\(canonicalShowID):s1:e1"
        )
        #expect(episode.value(forKey: "showLocalID") as? String == canonicalShowID)

        let showMetadata = try fetchMetadataRecord(
            in: controller,
            cacheID: "seriesguide:show:\(canonicalShowID)"
        )
        #expect(showMetadata.value(forKey: "title") as? String == "Imported Show")

        let episodeMetadata = try fetchMetadataRecord(
            in: controller,
            cacheID: "seriesguide:episode:seriesguide:episode:\(canonicalShowID):s1:e1"
        )
        #expect(episodeMetadata.value(forKey: "title") as? String == "Pilot")
    }

    @Test
    func seriesGuideMovieImportUsesExistingCanonicalLocalIDForMetadata() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let canonicalMovieID = "canonical-movie"
        let initialBackup = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [
                canonicalTrackedItem(
                    localID: canonicalMovieID,
                    kindRaw: "movie",
                    title: "Existing Movie",
                    tmdbID: 19913
                )
            ]
        )
        _ = try service.importCinueBackup(data: backupEncoder.encode(initialBackup))

        let seriesGuideJSON = """
        [
          {
            "tmdb_id": 19913,
            "title": "Imported Movie",
            "watched": false,
            "plays": 0
          }
        ]
        """

        _ = try service.importSeriesGuideMovies(data: Data(seriesGuideJSON.utf8))

        #expect(try trackedItemCount(in: controller) == 1)
        let metadata = try fetchMetadataRecord(
            in: controller,
            cacheID: "seriesguide:movie:\(canonicalMovieID)"
        )
        #expect(metadata.value(forKey: "title") as? String == "Imported Movie")
    }

    @Test
    func cinueBackupRoundTripsEpisodeRatingAndNotes() throws {
        let sourceController = PersistenceController(inMemory: true)
        let sourceService = BackupService(persistence: sourceController, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "title": "Altered Carbon",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401624, "episode": 2, "title": "Fallen Angel", "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        _ = try sourceService.importSeriesGuideShows(data: Data(json.utf8))
        try WatchStateStore(context: sourceController.container.viewContext, now: fixedDate)
            .updateEpisodePersonalDetails(
                localID: "seriesguide:episode:tmdb:1401624",
                userRating: 9,
                notes: "Episode note"
            )

        let data = try sourceService.exportCinueBackup()
        let document = try backupDecoder.decode(CinueBackupDocument.self, from: data)
        let exportedEpisode = try #require(document.episodeStates.first)
        #expect(exportedEpisode.userRating == 9)
        #expect(exportedEpisode.notes == "Episode note")

        let targetController = PersistenceController(inMemory: true)
        let targetService = BackupService(persistence: targetController, now: fixedDate)
        _ = try targetService.importCinueBackup(data: data)

        let importedEpisode = try fetchObject(
            in: targetController,
            entityName: "EpisodeState",
            localID: "seriesguide:episode:tmdb:1401624"
        )
        #expect((importedEpisode.value(forKey: "userRating") as? NSNumber)?.intValue == 9)
        #expect(importedEpisode.value(forKey: "notes") as? String == "Episode note")
    }

    @Test
    func cinueBackupRoundTripsNonSecretPreferences() throws {
        let sourceDefaults = try makeTestDefaults()
        defer { reset(defaults: sourceDefaults) }
        sourceDefaults.set(CinueAppearanceMode.dark.rawValue, forKey: CinuePreferenceKeys.appearanceMode)
        sourceDefaults.set(true, forKey: CinuePreferenceKeys.hideEpisodeSpoilers)
        sourceDefaults.set(true, forKey: CinuePreferenceKeys.useExactDates)
        sourceDefaults.set("en-US", forKey: CinuePreferenceKeys.tmdbLanguageCode)
        sourceDefaults.set(true, forKey: CinuePreferenceKeys.episodeNotificationsEnabled)
        sourceDefaults.set(3600.0, forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds)

        let sourceService = BackupService(
            persistence: PersistenceController(inMemory: true),
            now: fixedDate,
            userDefaults: sourceDefaults
        )

        let data = try sourceService.exportCinueBackup()
        let document = try backupDecoder.decode(CinueBackupDocument.self, from: data)
        #expect(document.preferences?.appearanceModeRaw == CinueAppearanceMode.dark.rawValue)
        #expect(document.preferences?.hideEpisodeSpoilers == true)
        #expect(document.preferences?.useExactDates == true)
        #expect(document.preferences?.tmdbLanguageCode == "en-US")
        #expect(document.preferences?.episodeNotificationsEnabled == true)
        #expect(document.preferences?.episodeNotificationLeadTimeSeconds == 3600.0)

        let targetDefaults = try makeTestDefaults()
        defer { reset(defaults: targetDefaults) }
        let targetService = BackupService(
            persistence: PersistenceController(inMemory: true),
            now: fixedDate,
            userDefaults: targetDefaults
        )

        _ = try targetService.importCinueBackup(data: data)

        #expect(targetDefaults.string(forKey: CinuePreferenceKeys.appearanceMode) == CinueAppearanceMode.dark.rawValue)
        #expect(targetDefaults.bool(forKey: CinuePreferenceKeys.hideEpisodeSpoilers) == true)
        #expect(targetDefaults.bool(forKey: CinuePreferenceKeys.useExactDates) == true)
        #expect(targetDefaults.string(forKey: CinuePreferenceKeys.tmdbLanguageCode) == "en-US")
        #expect(targetDefaults.bool(forKey: CinuePreferenceKeys.episodeNotificationsEnabled) == true)
        #expect(targetDefaults.double(forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds) == 3600.0)
    }

    @Test
    func importSeriesGuideShowsCreatesShowAndEpisodeStateItems() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 68421,
            "tvdb_id": 332331,
            "imdb_id": "tt2261227",
            "title": "Altered Carbon",
            "favorite": true,
            "hidden": false,
            "last_watched_ms": 1614593199175,
            "rating_user": 9,
            "user_note": "Stack watch",
            "seasons": [
              {
                "season": 1,
                "episodes": [
                  { "tmdb_id": 1401623, "watched": true, "plays": 2 },
                  { "tmdb_id": 1401624, "watched": false, "plays": 0 }
                ]
              }
            ]
          }
        ]
        """

        let summary = try service.importSeriesGuideShows(data: Data(json.utf8))

        #expect(summary.importedItems == 3)
        let item = try fetchTrackedItem(in: controller, localID: "seriesguide:show:tvdb:332331")
        #expect(item.value(forKey: "kindRaw") as? String == "show")
        #expect(item.value(forKey: "title") as? String == "Altered Carbon")
        #expect((item.value(forKey: "watchCount") as? NSNumber)?.intValue == 2)
        #expect(item.value(forKey: "isFavorite") as? Bool == true)
        #expect((item.value(forKey: "userRating") as? NSNumber)?.intValue == 9)

        let episode = try fetchObject(in: controller, entityName: "EpisodeState", localID: "seriesguide:episode:tmdb:1401623")
        #expect(episode.value(forKey: "showLocalID") as? String == "seriesguide:show:tvdb:332331")
        #expect((episode.value(forKey: "seasonNumber") as? NSNumber)?.intValue == 1)
        #expect(episode.value(forKey: "statusRaw") as? String == "watched")
        #expect((episode.value(forKey: "watchCount") as? NSNumber)?.intValue == 2)

        let metadata = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:show:seriesguide:show:tvdb:332331")
        #expect(metadata.value(forKey: "title") as? String == "Altered Carbon")
        #expect(metadata.value(forKey: "providerContentID") as? String == "tmdb:68421")
    }

    @Test
    func importSeriesGuideMoviesCreatesMovieTrackedItems() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 19913,
            "imdb_id": "tt1022603",
            "title": "(500) Days of Summer",
            "watched": true,
            "plays": 1,
            "in_watchlist": true,
            "last_updated_ms": 1619620588554
          }
        ]
        """

        let summary = try service.importBackup(data: Data(json.utf8))

        #expect(summary.importedItems == 1)
        let item = try fetchTrackedItem(in: controller, localID: "seriesguide:movie:tmdb:19913")
        #expect(item.value(forKey: "kindRaw") as? String == "movie")
        #expect(item.value(forKey: "title") as? String == "(500) Days of Summer")
        #expect(item.value(forKey: "statusRaw") as? String == "watched")
        #expect((item.value(forKey: "watchCount") as? NSNumber)?.intValue == 1)
        #expect(item.value(forKey: "isFavorite") as? Bool == true)

        let metadata = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19913")
        #expect(metadata.value(forKey: "title") as? String == "(500) Days of Summer")
        #expect(metadata.value(forKey: "sourceURLString") as? String == "https://www.themoviedb.org/movie/19913")
    }

    @Test
    func seriesGuideImportKeepsApprovedTMDBArtworkURL() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [{
          "tmdb_id": 19913,
          "title": "Approved artwork",
          "poster": "https://IMAGE.TMDB.ORG:443/t/p/w500/approved.jpg#fragment"
        }]
        """

        _ = try service.importSeriesGuideMovies(data: Data(json.utf8))

        let metadata = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19913")
        #expect(metadata.value(forKey: "posterURLString") as? String == "https://image.tmdb.org/t/p/w500/approved.jpg")
    }

    @Test
    func seriesGuideImportNormalizesProviderRelativeArtworkPaths() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          { "tmdb_id": 19913, "title": "Bare path", "poster": "poster.jpg" },
          { "tmdb_id": 19914, "title": "Slash path", "poster": "/leading.jpg" },
          { "tmdb_id": 19915, "title": "Empty path", "poster": "" },
          { "tmdb_id": 19916, "title": "Slash only", "poster": "/" }
        ]
        """

        _ = try service.importSeriesGuideMovies(data: Data(json.utf8))

        let barePath = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19913")
        let slashPath = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19914")
        let emptyPath = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19915")
        let slashOnly = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19916")

        #expect(barePath.value(forKey: "posterURLString") as? String == "https://image.tmdb.org/t/p/w500/poster.jpg")
        #expect(slashPath.value(forKey: "posterURLString") as? String == "https://image.tmdb.org/t/p/w500/leading.jpg")
        #expect(emptyPath.value(forKey: "posterURLString") as? String == nil)
        #expect(slashOnly.value(forKey: "posterURLString") as? String == nil)
    }

    @Test
    func seriesGuideImportDropsDisallowedAbsoluteArtworkURL() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [{
          "tmdb_id": 19913,
          "title": "Disallowed artwork",
          "poster": "https://evil.example/artwork.jpg"
        }]
        """

        _ = try service.importSeriesGuideMovies(data: Data(json.utf8))

        let metadata = try fetchMetadataRecord(in: controller, cacheID: "seriesguide:movie:seriesguide:movie:tmdb:19913")
        #expect(metadata.value(forKey: "posterURLString") as? String == nil)
    }

    @Test
    func backgroundImportSeriesGuideMoviesCreatesMovieTrackedItems() async throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "tmdb_id": 19913,
            "imdb_id": "tt1022603",
            "title": "(500) Days of Summer",
            "watched": true,
            "plays": 1,
            "in_watchlist": true,
            "last_updated_ms": 1619620588554
          }
        ]
        """

        let summary = try await service.importBackupInBackground(data: Data(json.utf8))

        #expect(summary.importedItems == 1)
        #expect(try trackedItemCount(in: controller) == 1)

        let item = try fetchTrackedItem(in: controller, localID: "seriesguide:movie:tmdb:19913")
        #expect(item.value(forKey: "title") as? String == "(500) Days of Summer")
    }

    @Test
    func importBackupFileReadsFilesPickerURLInBackground() async throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinue-backup-file-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("seriesguide-movies.json")
        let json = """
        [
          {
            "tmdb_id": 19913,
            "title": "(500) Days of Summer",
            "watched": true,
            "plays": 1,
            "in_watchlist": true
          }
        ]
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let summary = try await service.importBackupFile(at: fileURL)

        #expect(summary.source == "SeriesGuide movies")
        #expect(summary.importedItems == 1)
        #expect(try trackedItemCount(in: controller) == 1)
    }

    @Test
    func importSeriesGuideListsCreatesListsAndListItems() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = """
        [
          {
            "items": [
              { "externalId": "62425", "list_item_id": "62425-4-firstlist", "tvdb_id": 0, "type": "tmdb-show" }
            ],
            "list_id": "First%20list",
            "name": "First list",
            "order": 0
          }
        ]
        """

        let summary = try service.importBackup(data: Data(json.utf8))

        #expect(summary.source == "SeriesGuide lists")
        #expect(summary.importedItems == 2)
        let list = try fetchObject(in: controller, entityName: "UserList", localID: "seriesguide:list:First%20list")
        #expect(list.value(forKey: "name") as? String == "First list")
        let listItem = try fetchObject(in: controller, entityName: "UserListItem", localID: "seriesguide:listitem:62425-4-firstlist")
        #expect(listItem.value(forKey: "externalID") as? String == "62425")
        #expect(listItem.value(forKey: "kindRaw") as? String == "show")
        #expect((listItem.value(forKey: "tmdbID") as? NSNumber)?.intValue == 62425)
    }

    @Test
    func importBackupAutoDetectsCinueBackup() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let document = CinueBackupDocument(
            exportedAt: fixedDate(),
            trackedItems: [],
            lists: [
                CinueBackupList(
                    localID: "list-1",
                    name: "Weekend",
                    sortOrder: 0,
                    createdAt: fixedDate(),
                    updatedAt: fixedDate()
                )
            ]
        )

        let summary = try service.importBackup(data: backupEncoder.encode(document))

        #expect(summary.source == "Cinue backup")
        #expect(try entityCount(in: controller, entityName: "UserList") == 1)
    }

    @Test
    func importBackupAutoDetectsUTF32LEBOMSeriesGuideMovie() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = #"[{ "tmdb_id": 19913, "title": "(500) Days of Summer", "watched": true }]"#
        var data = Data([0xFF, 0xFE, 0x00, 0x00])
        data.append(try #require(json.data(using: .utf32LittleEndian)))

        let summary = try service.importBackup(data: data)

        #expect(summary.source == "SeriesGuide movies")
        #expect(summary.importedItems == 1)
        #expect(try trackedItemCount(in: controller) == 1)
    }

    @Test(arguments: backupImportEncodings)
    func importBackupAutoDetectsSupportedJSONEncodings(_ encoding: BackupImportEncoding) throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = #"[{ "tmdb_id": 19913, "title": "(500) Days of Summer", "watched": true }]"#

        let summary = try service.importBackup(data: encoding.data(for: json))

        #expect(summary.source == "SeriesGuide movies")
        #expect(summary.importedItems == 1)
        #expect(try trackedItemCount(in: controller) == 1)
    }

    @Test
    func importSeriesGuideMoviesDecodesUTF32LEBOMData() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = #"[{ "tmdb_id": 19913, "title": "(500) Days of Summer", "watched": true }]"#

        let summary = try service.importSeriesGuideMovies(
            data: utf32LittleEndianBOMData(for: json)
        )

        #expect(summary.source == "SeriesGuide movies")
        #expect(summary.importedItems == 1)
        #expect(try trackedItemCount(in: controller) == 1)
    }

    @Test
    func decodeSeriesGuideListsDecodesUTF32LEBOMData() throws {
        let controller = PersistenceController(inMemory: true)
        let service = BackupService(persistence: controller, now: fixedDate)
        let json = #"[{ "list_id": "watchlist", "name": "Watchlist", "order": 0, "items": [] }]"#

        let lists = try service.decodeSeriesGuideLists(data: utf32LittleEndianBOMData(for: json))

        #expect(lists.count == 1)
    }

}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

private let backupEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let backupDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

struct BackupImportEncoding: Sendable {
    let name: String
    let stringEncoding: String.Encoding
    let bom: Data

    func data(for json: String) -> Data {
        var data = bom
        data.append(json.data(using: stringEncoding)!)
        return data
    }
}

extension BackupImportEncoding: CustomTestStringConvertible {
    var testDescription: String {
        name
    }
}

private let backupImportEncodings: [BackupImportEncoding] = [
    .init(name: "UTF-8 without BOM", stringEncoding: .utf8, bom: Data()),
    .init(name: "UTF-8 with BOM", stringEncoding: .utf8, bom: Data([0xEF, 0xBB, 0xBF])),
    .init(name: "UTF-16BE without BOM", stringEncoding: .utf16BigEndian, bom: Data()),
    .init(name: "UTF-16BE with BOM", stringEncoding: .utf16BigEndian, bom: Data([0xFE, 0xFF])),
    .init(name: "UTF-16LE without BOM", stringEncoding: .utf16LittleEndian, bom: Data()),
    .init(name: "UTF-16LE with BOM", stringEncoding: .utf16LittleEndian, bom: Data([0xFF, 0xFE])),
    .init(name: "UTF-32BE without BOM", stringEncoding: .utf32BigEndian, bom: Data()),
    .init(name: "UTF-32BE with BOM", stringEncoding: .utf32BigEndian, bom: Data([0x00, 0x00, 0xFE, 0xFF])),
    .init(name: "UTF-32LE without BOM", stringEncoding: .utf32LittleEndian, bom: Data()),
    .init(name: "UTF-32LE with BOM", stringEncoding: .utf32LittleEndian, bom: Data([0xFF, 0xFE, 0x00, 0x00]))
]

private func utf32LittleEndianBOMData(for json: String) -> Data {
    var data = Data([0xFF, 0xFE, 0x00, 0x00])
    data.append(json.data(using: .utf32LittleEndian)!)
    return data
}

private func makeTestDefaults() throws -> UserDefaults {
    let suiteName = "com.nihal.Cinue.BackupServiceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__testSuiteName")
    return defaults
}

private func testImportPolicy(
    maximumFileBytes: Int = 1_024,
    maximumTopLevelRecords: Int = 10,
    maximumNestedEpisodes: Int = 10,
    maximumAggregateRecords: Int = 10,
    maximumStringUTF8Bytes: Int = 1_024,
    maximumJSONNestingDepth: Int = 10
) -> BackupImportPolicy {
    BackupImportPolicy(
        maximumFileBytes: maximumFileBytes,
        maximumTopLevelRecords: maximumTopLevelRecords,
        maximumNestedEpisodes: maximumNestedEpisodes,
        maximumAggregateRecords: maximumAggregateRecords,
        maximumStringUTF8Bytes: maximumStringUTF8Bytes,
        maximumJSONNestingDepth: maximumJSONNestingDepth
    )
}

private func makeCinueTrackedItem(
    watchCount: Int,
    userRating: Int? = nil
) -> CinueBackupTrackedItem {
    CinueBackupTrackedItem(
        localID: "tracked-1",
        kindRaw: "movie",
        title: "Tracked",
        sortTitle: "tracked",
        tvdbID: nil,
        tmdbID: 1,
        imdbID: nil,
        statusRaw: "watched",
        watchCount: watchCount,
        watchedAt: nil,
        isCollected: false,
        isFavorite: false,
        isHidden: false,
        userRating: userRating,
        notes: nil,
        createdAt: fixedDate(),
        updatedAt: fixedDate()
    )
}

private func canonicalTrackedItem(
    localID: String,
    kindRaw: String,
    title: String,
    tmdbID: Int
) -> CinueBackupTrackedItem {
    CinueBackupTrackedItem(
        localID: localID,
        kindRaw: kindRaw,
        title: title,
        sortTitle: title.localizedLowercase,
        tvdbID: nil,
        tmdbID: tmdbID,
        imdbID: nil,
        statusRaw: "unwatched",
        watchCount: 0,
        watchedAt: nil,
        isCollected: false,
        isFavorite: false,
        isHidden: false,
        userRating: nil,
        notes: nil,
        createdAt: fixedDate(),
        updatedAt: fixedDate()
    )
}

private func canonicalEpisodeState(
    localID: String,
    showLocalID: String
) -> CinueBackupEpisodeState {
    CinueBackupEpisodeState(
        localID: localID,
        showLocalID: showLocalID,
        seasonNumber: 1,
        episodeNumber: 1,
        title: "Episode",
        tvdbID: nil,
        tmdbID: nil,
        statusRaw: "unwatched",
        watchCount: 0,
        watchedAt: nil,
        isCollected: false,
        isSkipped: false,
        userRating: nil,
        notes: nil,
        createdAt: fixedDate(),
        updatedAt: fixedDate()
    )
}

private func canonicalUserList(localID: String, name: String) -> CinueBackupList {
    CinueBackupList(
        localID: localID,
        name: name,
        sortOrder: 0,
        createdAt: fixedDate(),
        updatedAt: fixedDate()
    )
}

private func canonicalUserListItem(
    localID: String,
    listLocalID: String,
    itemLocalID: String
) -> CinueBackupListItem {
    CinueBackupListItem(
        localID: localID,
        listLocalID: listLocalID,
        itemLocalID: itemLocalID,
        externalID: nil,
        kindRaw: "show",
        tvdbID: nil,
        tmdbID: 42,
        sortOrder: 0,
        createdAt: fixedDate(),
        updatedAt: fixedDate()
    )
}

private func makeCinueEpisodeState(
    seasonNumber: Int = 1,
    episodeNumber: Int? = 1,
    watchCount: Int = 0,
    userRating: Int? = nil
) -> CinueBackupEpisodeState {
    CinueBackupEpisodeState(
        localID: "episode-1",
        showLocalID: "show-1",
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        title: "Episode",
        tvdbID: nil,
        tmdbID: 1,
        statusRaw: "unwatched",
        watchCount: watchCount,
        watchedAt: nil,
        isCollected: false,
        isSkipped: false,
        userRating: userRating,
        notes: nil,
        createdAt: fixedDate(),
        updatedAt: fixedDate()
    )
}

private enum ExpectedSaveFailure: Error {
    case failed
}

private func importedPreferences() -> CinueBackupPreferences {
    CinueBackupPreferences(
        appearanceModeRaw: CinueAppearanceMode.dark.rawValue,
        hideEpisodeSpoilers: true,
        useExactDates: false,
        tmdbLanguageCode: "en-US",
        episodeNotificationsEnabled: true,
        episodeNotificationLeadTimeSeconds: 3600.0
    )
}

private func setOriginalPreferences(in defaults: UserDefaults) {
    defaults.set(CinueAppearanceMode.light.rawValue, forKey: CinuePreferenceKeys.appearanceMode)
    defaults.set(false, forKey: CinuePreferenceKeys.hideEpisodeSpoilers)
    defaults.set(true, forKey: CinuePreferenceKeys.useExactDates)
    defaults.set("fr-FR", forKey: CinuePreferenceKeys.tmdbLanguageCode)
    defaults.set(false, forKey: CinuePreferenceKeys.episodeNotificationsEnabled)
    defaults.set(120.0, forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds)
}

private func expectOriginalPreferences(in defaults: UserDefaults) {
    #expect(defaults.string(forKey: CinuePreferenceKeys.appearanceMode) == CinueAppearanceMode.light.rawValue)
    #expect(defaults.bool(forKey: CinuePreferenceKeys.hideEpisodeSpoilers) == false)
    #expect(defaults.bool(forKey: CinuePreferenceKeys.useExactDates) == true)
    #expect(defaults.string(forKey: CinuePreferenceKeys.tmdbLanguageCode) == "fr-FR")
    #expect(defaults.bool(forKey: CinuePreferenceKeys.episodeNotificationsEnabled) == false)
    #expect(defaults.double(forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds) == 120.0)
}

private func reset(defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__testSuiteName") else {
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
}

@MainActor
private func insertTrackedItem(
    into controller: PersistenceController,
    localID: String,
    kindRaw: String,
    title: String,
    tvdbID: Int?,
    tmdbID: Int?,
    imdbID: String?,
    statusRaw: String,
    watchCount: Int,
    isFavorite: Bool
) throws {
    let context = controller.container.viewContext
    let item = NSEntityDescription.insertNewObject(forEntityName: "TrackedItem", into: context)
    let now = fixedDate()

    item.setValue(localID, forKey: "localID")
    item.setValue(kindRaw, forKey: "kindRaw")
    item.setValue(title, forKey: "title")
    item.setValue(title.localizedLowercase, forKey: "sortTitle")
    item.setValue(tvdbID, forKey: "tvdbID")
    item.setValue(tmdbID, forKey: "tmdbID")
    item.setValue(imdbID, forKey: "imdbID")
    item.setValue(statusRaw, forKey: "statusRaw")
    item.setValue(Int32(watchCount), forKey: "watchCount")
    item.setValue(false, forKey: "isCollected")
    item.setValue(isFavorite, forKey: "isFavorite")
    item.setValue(false, forKey: "isHidden")
    item.setValue(now, forKey: "createdAt")
    item.setValue(now, forKey: "updatedAt")

    try context.save()
}

@MainActor
private func trackedItemCount(in controller: PersistenceController) throws -> Int {
    try controller.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "TrackedItem"))
}

@MainActor
private func fetchTrackedItem(in controller: PersistenceController, localID: String) throws -> NSManagedObject {
    try fetchObject(in: controller, entityName: "TrackedItem", localID: localID)
}

@MainActor
private func entityCount(in controller: PersistenceController, entityName: String) throws -> Int {
    try controller.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entityName))
}

@MainActor
private func expectImportableEntityCountsAreZero(in controller: PersistenceController) throws {
    #expect(try entityCount(in: controller, entityName: "TrackedItem") == 0)
    #expect(try entityCount(in: controller, entityName: "EpisodeState") == 0)
    #expect(try entityCount(in: controller, entityName: "UserList") == 0)
    #expect(try entityCount(in: controller, entityName: "UserListItem") == 0)
}

@MainActor
private func fetchObject(in controller: PersistenceController, entityName: String, localID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.predicate = NSPredicate(format: "localID == %@", localID)

    return try #require(controller.container.viewContext.fetch(request).first)
}

@MainActor
private func fetchMetadataRecord(in controller: PersistenceController, cacheID: String) throws -> NSManagedObject {
    let request = NSFetchRequest<NSManagedObject>(entityName: "MetadataRecord")
    request.predicate = NSPredicate(format: "cacheID == %@", cacheID)

    return try #require(controller.container.viewContext.fetch(request).first)
}
