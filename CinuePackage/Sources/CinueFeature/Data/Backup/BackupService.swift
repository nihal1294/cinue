import CoreData
import Darwin
import Foundation

final class BackupService: @unchecked Sendable {
    private let persistence: PersistenceController
    private let now: @Sendable () -> Date
    private let userDefaults: UserDefaults
    private let importPolicy: BackupImportPolicy
    private let contextSave: (NSManagedObjectContext) throws -> Void

    init(
        persistence: PersistenceController,
        now: @escaping @Sendable () -> Date = Date.init,
        userDefaults: UserDefaults = .standard,
        importPolicy: BackupImportPolicy = .standard,
        contextSave: @escaping (NSManagedObjectContext) throws -> Void = { context in
            if context.hasChanges {
                try context.save()
            }
        }
    ) {
        self.persistence = persistence
        self.now = now
        self.userDefaults = userDefaults
        self.importPolicy = importPolicy
        self.contextSave = contextSave
    }

    func exportCinueBackup() throws -> Data {
        let document = CinueBackupDocument(
            exportedAt: now(),
            trackedItems: try fetchTrackedItems().map(makeBackupItem),
            episodeStates: try fetchEpisodeStates().map(makeBackupEpisodeState),
            lists: try fetchUserLists().map(makeBackupList),
            listItems: try fetchUserListItems().map(makeBackupListItem),
            preferences: makeBackupPreferences()
        )
        return try Self.encoder.encode(document)
    }

    func importBackup(data: Data) throws -> BackupImportSummary {
        try validateFileByteCount(data.count)
        return try importSynchronously(data: data, kind: nil)
    }

    func importBackupFile(at url: URL) async throws -> BackupImportSummary {
        let policy = importPolicy
        let data = try await Task.detached(priority: .userInitiated) {
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues.isRegularFile == true,
                  let fileSize = resourceValues.fileSize else {
                throw BackupImportError.invalidPayload
            }

            let validator = BackupImportValidator(policy: policy)
            try validator.validateFileByteCount(fileSize)

            let fileDescriptor = try Self.openReadOnlyFileDescriptor(at: url)
            var descriptorNeedsClose = true
            defer {
                if descriptorNeedsClose {
                    _ = Darwin.close(fileDescriptor)
                }
            }

            let openedFileSize = try Self.openedRegularFileSize(fileDescriptor)
            try validator.validateFileByteCount(openedFileSize)

            let fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
            descriptorNeedsClose = false
            defer {
                try? fileHandle.close()
            }

            return try Self.readBoundedData(from: fileHandle, policy: policy)
        }.value

        try validateFileByteCount(data.count)

        return try await importBackupInBackground(data: data)
    }

    private static func openReadOnlyFileDescriptor(at url: URL) throws -> Int32 {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw BackupImportError.invalidPayload
            }

            let fileDescriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
            guard fileDescriptor >= 0 else {
                let errorNumber = errno
                throw POSIXError(POSIXErrorCode(rawValue: errorNumber) ?? .EIO)
            }

            return fileDescriptor
        }
    }

    private static func openedRegularFileSize(_ fileDescriptor: Int32) throws -> Int {
        var attributes = stat()
        guard fstat(fileDescriptor, &attributes) == 0,
              (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_size >= 0 else {
            throw BackupImportError.invalidPayload
        }

        return Int(exactly: attributes.st_size) ?? Int.max
    }

    private static func readBoundedData(
        from fileHandle: FileHandle,
        policy: BackupImportPolicy
    ) throws -> Data {
        let detectionLimit = policy.maximumFileBytes.addingReportingOverflow(1)
        let maximumReadableBytes = detectionLimit.overflow
            ? Int.max
            : detectionLimit.partialValue
        let validator = BackupImportValidator(policy: policy)
        var data = Data()

        while data.count < maximumReadableBytes {
            let remaining = maximumReadableBytes - data.count
            let readCount = min(64 * 1_024, remaining)
            guard let chunk = try fileHandle.read(upToCount: readCount), chunk.isEmpty == false else {
                break
            }

            data.append(chunk)
        }

        try validator.validateFileByteCount(data.count)
        return data
    }

    func importBackupInBackground(data: Data) async throws -> BackupImportSummary {
        try validateFileByteCount(data.count)
        let context = makeImportContext()

        return try await context.perform {
            try self.transactionalImport(data: data, context: context, kind: nil)
        }
    }

    func importCinueBackup(data: Data) throws -> BackupImportSummary {
        try validateFileByteCount(data.count)
        return try importSynchronously(data: data, kind: .cinue)
    }

    private func mutateCinueBackup(
        _ document: CinueBackupDocument,
        context: NSManagedObjectContext
    ) throws -> BackupImportSummary {
        let cache = try ImportLookupCache(context: context)
        var summary = BackupImportSummary(importedItems: 0, updatedItems: 0, skippedItems: 0, source: "Cinue backup")
        var canonicalTrackedLocalIDs: [String: String] = [:]

        for item in document.trackedItems {
            let canonicalLocalID = cache.trackedItem(
                localID: item.localID,
                kindRaw: item.kindRaw,
                tvdbID: item.tvdbID,
                tmdbID: item.tmdbID,
                imdbID: item.imdbID
            )?.stringValue(forKey: "localID") ?? item.localID
            let result = try upsertTrackedItem(
                context: context,
                cache: cache,
                localID: item.localID,
                kindRaw: item.kindRaw,
                title: item.title,
                sortTitle: item.sortTitle,
                tvdbID: item.tvdbID,
                tmdbID: item.tmdbID,
                imdbID: item.imdbID,
                statusRaw: item.statusRaw,
                watchCount: item.watchCount,
                watchedAt: item.watchedAt,
                isCollected: item.isCollected ?? false,
                isFavorite: item.isFavorite,
                isHidden: item.isHidden,
                userRating: item.userRating,
                notes: item.notes,
                createdAt: item.createdAt
            )
            apply(result, to: &summary)
            canonicalTrackedLocalIDs[item.localID] = canonicalLocalID
        }

        for episode in document.episodeStates {
            let result = try upsertEpisodeState(
                context: context,
                cache: cache,
                localID: episode.localID,
                showLocalID: canonicalTrackedLocalIDs[episode.showLocalID] ?? episode.showLocalID,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                title: episode.title,
                tvdbID: episode.tvdbID,
                tmdbID: episode.tmdbID,
                statusRaw: episode.statusRaw,
                watchCount: episode.watchCount,
                watchedAt: episode.watchedAt,
                isCollected: episode.isCollected,
                isSkipped: episode.isSkipped,
                userRating: episode.userRating,
                notes: episode.notes,
                createdAt: episode.createdAt
            )
            apply(result, to: &summary)
        }

        for list in document.lists {
            let result = try upsertUserList(
                context: context,
                cache: cache,
                localID: list.localID,
                name: list.name,
                sortOrder: list.sortOrder,
                createdAt: list.createdAt
            )
            apply(result, to: &summary)
        }

        for listItem in document.listItems {
            let result = try upsertUserListItem(
                context: context,
                cache: cache,
                localID: listItem.localID,
                listLocalID: listItem.listLocalID,
                itemLocalID: listItem.itemLocalID.map {
                    canonicalTrackedLocalIDs[$0] ?? $0
                },
                externalID: listItem.externalID,
                kindRaw: listItem.kindRaw,
                tvdbID: listItem.tvdbID,
                tmdbID: listItem.tmdbID,
                sortOrder: listItem.sortOrder,
                createdAt: listItem.createdAt
            )
            apply(result, to: &summary)
        }

        return summary
    }

    func importSeriesGuideShows(data: Data) throws -> BackupImportSummary {
        try validateFileByteCount(data.count)
        return try importSynchronously(data: data, kind: .seriesGuideShows)
    }

    private func mutateSeriesGuideShows(
        _ shows: [SeriesGuideShowBackup],
        context: NSManagedObjectContext
    ) throws -> BackupImportSummary {
        let cache = try ImportLookupCache(context: context)
        var summary = BackupImportSummary(importedItems: 0, updatedItems: 0, skippedItems: 0, source: "SeriesGuide shows")

        for show in shows {
            guard show.tmdbID != nil || show.tvdbID != nil || show.imdbID != nil else {
                summary.skippedItems += 1
                continue
            }

            let importedShowLocalID = show.localID
            let showLocalID = cache.trackedItem(
                localID: importedShowLocalID,
                kindRaw: MediaKind.show.rawValue,
                tvdbID: show.tvdbID,
                tmdbID: show.tmdbID,
                imdbID: show.imdbID
            )?.stringValue(forKey: "localID") ?? importedShowLocalID
            let watchedEpisodes = show.watchedEpisodeCount
            let totalPlays = try totalEpisodePlays(for: show)
            let status: WatchStatus = watchedEpisodes > 0 ? .watching : .unwatched
            let result = try upsertTrackedItem(
                context: context,
                cache: cache,
                localID: importedShowLocalID,
                kindRaw: MediaKind.show.rawValue,
                title: show.title ?? "Imported Show",
                sortTitle: show.title?.localizedLowercase,
                tvdbID: show.tvdbID,
                tmdbID: show.tmdbID,
                imdbID: show.imdbID,
                statusRaw: status.rawValue,
                watchCount: totalPlays,
                watchedAt: Self.date(milliseconds: show.lastWatchedMilliseconds),
                isCollected: false,
                isFavorite: show.favorite ?? false,
                isHidden: show.hidden ?? false,
                userRating: show.ratingUser,
                notes: show.userNote,
                createdAt: now()
            )
            apply(result, to: &summary)
            try upsertMetadataRecord(
                context: context,
                cache: cache,
                cacheID: "seriesguide:show:\(showLocalID)",
                providerRaw: "seriesguide",
                providerContentID: show.providerContentID,
                kindRaw: MediaKind.show.rawValue,
                title: show.title ?? "Imported Show",
                overview: show.overview,
                posterURLString: Self.tmdbImageURLString(show.poster, size: .poster),
                backdropURLString: nil,
                releaseDate: Self.iso8601Date(show.firstAired),
                sourceURLString: Self.tmdbSourceURLString(kind: .show, tmdbID: show.tmdbID),
                rawJSON: try? Self.encoder.encode(show)
            )

            for season in show.seasons ?? [] {
                for episode in season.episodes ?? [] {
                    let result = try upsertEpisodeState(
                        context: context,
                        cache: cache,
                        localID: episode.localID(showLocalID: showLocalID, seasonNumber: season.season ?? 0),
                        showLocalID: showLocalID,
                        seasonNumber: season.season ?? 0,
                        episodeNumber: episode.episode,
                        title: episode.title,
                        tvdbID: episode.tvdbID,
                        tmdbID: episode.tmdbID,
                        statusRaw: episode.watchStatus.rawValue,
                        watchCount: episode.importedPlayCount,
                        watchedAt: episode.watched == true ? Self.date(milliseconds: show.lastWatchedMilliseconds) : nil,
                        isCollected: episode.collected ?? false,
                        isSkipped: episode.skipped ?? false,
                        userRating: nil,
                        notes: nil,
                        createdAt: now()
                    )
                    apply(result, to: &summary)
                    try upsertMetadataRecord(
                        context: context,
                        cache: cache,
                        cacheID: "seriesguide:episode:\(episode.localID(showLocalID: showLocalID, seasonNumber: season.season ?? 0))",
                        providerRaw: "seriesguide",
                        providerContentID: episode.providerContentID,
                        kindRaw: "episode",
                        title: episode.title ?? "Episode \(episode.episode ?? 0)",
                        overview: episode.overview,
                        posterURLString: nil,
                        backdropURLString: Self.tmdbImageURLString(episode.image, size: .backdrop),
                        releaseDate: Self.date(milliseconds: episode.firstAiredMilliseconds),
                        sourceURLString: Self.tmdbEpisodeSourceURLString(
                            showTMDBID: show.tmdbID,
                            seasonNumber: season.season,
                            episodeNumber: episode.episode
                        ),
                        rawJSON: nil
                    )
                }
            }
        }

        return summary
    }

    func importSeriesGuideMovies(data: Data) throws -> BackupImportSummary {
        try validateFileByteCount(data.count)
        return try importSynchronously(data: data, kind: .seriesGuideMovies)
    }

    private func mutateSeriesGuideMovies(
        _ movies: [SeriesGuideMovieBackup],
        context: NSManagedObjectContext
    ) throws -> BackupImportSummary {
        let cache = try ImportLookupCache(context: context)
        var summary = BackupImportSummary(importedItems: 0, updatedItems: 0, skippedItems: 0, source: "SeriesGuide movies")

        for movie in movies {
            guard movie.tmdbID != nil || movie.imdbID != nil else {
                summary.skippedItems += 1
                continue
            }

            let isWatched = movie.watched ?? false
            let importedMovieLocalID = movie.localID
            let movieLocalID = cache.trackedItem(
                localID: importedMovieLocalID,
                kindRaw: MediaKind.movie.rawValue,
                tvdbID: nil,
                tmdbID: movie.tmdbID,
                imdbID: movie.imdbID
            )?.stringValue(forKey: "localID") ?? importedMovieLocalID
            let result = try upsertTrackedItem(
                context: context,
                cache: cache,
                localID: importedMovieLocalID,
                kindRaw: MediaKind.movie.rawValue,
                title: movie.title ?? "Imported Movie",
                sortTitle: movie.title?.localizedLowercase,
                tvdbID: nil,
                tmdbID: movie.tmdbID,
                imdbID: movie.imdbID,
                statusRaw: isWatched ? WatchStatus.watched.rawValue : WatchStatus.unwatched.rawValue,
                watchCount: movie.plays ?? (isWatched ? 1 : 0),
                watchedAt: isWatched ? Self.date(milliseconds: movie.lastUpdatedMilliseconds) : nil,
                isCollected: movie.inCollection ?? false,
                isFavorite: movie.inWatchlist ?? false,
                isHidden: false,
                userRating: nil,
                notes: nil,
                createdAt: now()
            )
            apply(result, to: &summary)
            try upsertMetadataRecord(
                context: context,
                cache: cache,
                cacheID: "seriesguide:movie:\(movieLocalID)",
                providerRaw: "seriesguide",
                providerContentID: movie.providerContentID,
                kindRaw: MediaKind.movie.rawValue,
                title: movie.title ?? "Imported Movie",
                overview: movie.overview,
                posterURLString: Self.tmdbImageURLString(movie.poster, size: .poster),
                backdropURLString: nil,
                releaseDate: Self.date(milliseconds: movie.releasedMilliseconds),
                sourceURLString: Self.tmdbSourceURLString(kind: .movie, tmdbID: movie.tmdbID),
                rawJSON: try? Self.encoder.encode(movie)
            )
        }

        return summary
    }

    func importSeriesGuideLists(data: Data) throws -> BackupImportSummary {
        try validateFileByteCount(data.count)
        return try importSynchronously(data: data, kind: .seriesGuideLists)
    }

    private func mutateSeriesGuideLists(
        _ lists: [SeriesGuideListBackup],
        context: NSManagedObjectContext
    ) throws -> BackupImportSummary {
        let cache = try ImportLookupCache(context: context)
        var summary = BackupImportSummary(importedItems: 0, updatedItems: 0, skippedItems: 0, source: "SeriesGuide lists")

        for list in lists {
            guard let name = list.name, name.isEmpty == false else {
                summary.skippedItems += 1
                continue
            }

            let listLocalID = list.localID
            let listResult = try upsertUserList(
                context: context,
                cache: cache,
                localID: listLocalID,
                name: name,
                sortOrder: list.order ?? 0,
                createdAt: now()
            )
            apply(listResult, to: &summary)

            for (index, item) in (list.items ?? []).enumerated() {
                let mapped = item.mappedListItem(listLocalID: listLocalID, sortOrder: index)
                let itemResult = try upsertUserListItem(
                    context: context,
                    cache: cache,
                    localID: mapped.localID,
                    listLocalID: listLocalID,
                    itemLocalID: mapped.itemLocalID,
                    externalID: mapped.externalID,
                    kindRaw: mapped.kindRaw,
                    tvdbID: mapped.tvdbID,
                    tmdbID: mapped.tmdbID,
                    sortOrder: mapped.sortOrder,
                    createdAt: now()
                )
                apply(itemResult, to: &summary)
            }
        }

        return summary
    }

    func decodeSeriesGuideLists(data: Data) throws -> [SeriesGuideListBackup] {
        try validateFileByteCount(data.count)
        let validator = BackupImportValidator(policy: importPolicy)
        let preparedJSON = try validator.prepareAndValidateSerializedJSON(data)
        let lists = try decode([SeriesGuideListBackup].self, from: preparedJSON.foundationData)
        try validator.validate(lists)
        return lists
    }

    private func validateFileByteCount(_ byteCount: Int) throws {
        try BackupImportValidator(policy: importPolicy).validateFileByteCount(byteCount)
    }

    private func decode<Document: Decodable>(_ type: Document.Type, from data: Data) throws -> Document {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw BackupImportError.invalidPayload
        }
    }

    private func importSynchronously(
        data: Data,
        kind: BackupKind?
    ) throws -> BackupImportSummary {
        let context = makeImportContext()
        return try context.performAndWait {
            try self.transactionalImport(data: data, context: context, kind: kind)
        }
    }

    private func makeImportContext() -> NSManagedObjectContext {
        let context = persistence.container.newBackgroundContext()
        context.name = "CinueBackupImport"
        context.undoManager = nil
        context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        return context
    }

    private func transactionalImport(
        data: Data,
        context: NSManagedObjectContext,
        kind: BackupKind?
    ) throws -> BackupImportSummary {
        do {
            let result = try decodeValidateAndMutate(
                data: data,
                context: context,
                kind: kind
            )
            try contextSave(context)
            applyBackupPreferences(result.preferences)
            return result.summary
        } catch {
            context.rollback()
            throw error
        }
    }

    private func decodeValidateAndMutate(
        data: Data,
        context: NSManagedObjectContext,
        kind: BackupKind?
    ) throws -> BackupImportResult {
        let validator = BackupImportValidator(policy: importPolicy)
        let preparedJSON = try validator.prepareAndValidateSerializedJSON(data)
        let backupKind = try kind ?? detectBackupKind(json: preparedJSON.root)

        switch backupKind {
        case .cinue:
            let document = try decode(CinueBackupDocument.self, from: preparedJSON.foundationData)
            try validator.validate(document)
            return BackupImportResult(
                summary: try mutateCinueBackup(document, context: context),
                preferences: document.preferences
            )
        case .seriesGuideShows:
            let shows = try decode([SeriesGuideShowBackup].self, from: preparedJSON.foundationData)
            try validator.validate(shows)
            return BackupImportResult(
                summary: try mutateSeriesGuideShows(shows, context: context),
                preferences: nil
            )
        case .seriesGuideMovies:
            let movies = try decode([SeriesGuideMovieBackup].self, from: preparedJSON.foundationData)
            try validator.validate(movies)
            return BackupImportResult(
                summary: try mutateSeriesGuideMovies(movies, context: context),
                preferences: nil
            )
        case .seriesGuideLists:
            let lists = try decode([SeriesGuideListBackup].self, from: preparedJSON.foundationData)
            try validator.validate(lists)
            return BackupImportResult(
                summary: try mutateSeriesGuideLists(lists, context: context),
                preferences: nil
            )
        }
    }

    private func fetchTrackedItems() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TrackedItem")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortTitle", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        return try persistence.container.viewContext.fetch(request)
    }

    private func fetchEpisodeStates() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "EpisodeState")
        request.sortDescriptors = [
            NSSortDescriptor(key: "showLocalID", ascending: true),
            NSSortDescriptor(key: "seasonNumber", ascending: true),
            NSSortDescriptor(key: "episodeNumber", ascending: true)
        ]
        return try persistence.container.viewContext.fetch(request)
    }

    private func fetchUserLists() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserList")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return try persistence.container.viewContext.fetch(request)
    }

    private func fetchUserListItems() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserListItem")
        request.sortDescriptors = [
            NSSortDescriptor(key: "listLocalID", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true)
        ]
        return try persistence.container.viewContext.fetch(request)
    }

    private func makeBackupItem(_ object: NSManagedObject) -> CinueBackupTrackedItem {
        CinueBackupTrackedItem(
            localID: object.stringValue(forKey: "localID"),
            kindRaw: object.stringValue(forKey: "kindRaw"),
            title: object.stringValue(forKey: "title"),
            sortTitle: object.value(forKey: "sortTitle") as? String,
            tvdbID: object.intValue(forKey: "tvdbID"),
            tmdbID: object.intValue(forKey: "tmdbID"),
            imdbID: object.value(forKey: "imdbID") as? String,
            statusRaw: object.stringValue(forKey: "statusRaw"),
            watchCount: object.primitiveIntValue(forKey: "watchCount"),
            watchedAt: object.value(forKey: "watchedAt") as? Date,
            isCollected: object.primitiveBoolValue(forKey: "isCollected"),
            isFavorite: object.primitiveBoolValue(forKey: "isFavorite"),
            isHidden: object.primitiveBoolValue(forKey: "isHidden"),
            userRating: object.intValue(forKey: "userRating"),
            notes: object.value(forKey: "notes") as? String,
            createdAt: object.dateValue(forKey: "createdAt", fallback: now()),
            updatedAt: object.dateValue(forKey: "updatedAt", fallback: now())
        )
    }

    private func makeBackupEpisodeState(_ object: NSManagedObject) -> CinueBackupEpisodeState {
        CinueBackupEpisodeState(
            localID: object.stringValue(forKey: "localID"),
            showLocalID: object.stringValue(forKey: "showLocalID"),
            seasonNumber: object.primitiveIntValue(forKey: "seasonNumber"),
            episodeNumber: object.intValue(forKey: "episodeNumber"),
            title: object.value(forKey: "title") as? String,
            tvdbID: object.intValue(forKey: "tvdbID"),
            tmdbID: object.intValue(forKey: "tmdbID"),
            statusRaw: object.stringValue(forKey: "statusRaw"),
            watchCount: object.primitiveIntValue(forKey: "watchCount"),
            watchedAt: object.value(forKey: "watchedAt") as? Date,
            isCollected: object.primitiveBoolValue(forKey: "isCollected"),
            isSkipped: object.primitiveBoolValue(forKey: "isSkipped"),
            userRating: object.intValue(forKey: "userRating"),
            notes: object.value(forKey: "notes") as? String,
            createdAt: object.dateValue(forKey: "createdAt", fallback: now()),
            updatedAt: object.dateValue(forKey: "updatedAt", fallback: now())
        )
    }

    private func makeBackupList(_ object: NSManagedObject) -> CinueBackupList {
        CinueBackupList(
            localID: object.stringValue(forKey: "localID"),
            name: object.stringValue(forKey: "name"),
            sortOrder: object.primitiveIntValue(forKey: "sortOrder"),
            createdAt: object.dateValue(forKey: "createdAt", fallback: now()),
            updatedAt: object.dateValue(forKey: "updatedAt", fallback: now())
        )
    }

    private func makeBackupListItem(_ object: NSManagedObject) -> CinueBackupListItem {
        CinueBackupListItem(
            localID: object.stringValue(forKey: "localID"),
            listLocalID: object.stringValue(forKey: "listLocalID"),
            itemLocalID: object.value(forKey: "itemLocalID") as? String,
            externalID: object.value(forKey: "externalID") as? String,
            kindRaw: object.stringValue(forKey: "kindRaw"),
            tvdbID: object.intValue(forKey: "tvdbID"),
            tmdbID: object.intValue(forKey: "tmdbID"),
            sortOrder: object.primitiveIntValue(forKey: "sortOrder"),
            createdAt: object.dateValue(forKey: "createdAt", fallback: now()),
            updatedAt: object.dateValue(forKey: "updatedAt", fallback: now())
        )
    }

    private func makeBackupPreferences() -> CinueBackupPreferences {
        CinueBackupPreferences(
            appearanceModeRaw: userDefaults.string(forKey: CinuePreferenceKeys.appearanceMode)
                ?? CinueAppearanceMode.system.rawValue,
            hideEpisodeSpoilers: userDefaults.bool(forKey: CinuePreferenceKeys.hideEpisodeSpoilers),
            useExactDates: userDefaults.bool(forKey: CinuePreferenceKeys.useExactDates),
            tmdbLanguageCode: userDefaults.string(forKey: CinuePreferenceKeys.tmdbLanguageCode),
            episodeNotificationsEnabled: userDefaults.bool(forKey: CinuePreferenceKeys.episodeNotificationsEnabled),
            episodeNotificationLeadTimeSeconds: userDefaults.double(
                forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds
            )
        )
    }

    private func applyBackupPreferences(_ preferences: CinueBackupPreferences?) {
        guard let preferences else {
            return
        }

        if let appearanceModeRaw = preferences.appearanceModeRaw,
           let appearanceMode = CinueAppearanceMode(rawValue: appearanceModeRaw) {
            userDefaults.set(appearanceMode.rawValue, forKey: CinuePreferenceKeys.appearanceMode)
        }

        if let hideEpisodeSpoilers = preferences.hideEpisodeSpoilers {
            userDefaults.set(hideEpisodeSpoilers, forKey: CinuePreferenceKeys.hideEpisodeSpoilers)
        }

        if let useExactDates = preferences.useExactDates {
            userDefaults.set(useExactDates, forKey: CinuePreferenceKeys.useExactDates)
        }

        if let tmdbLanguageCode = preferences.tmdbLanguageCode {
            userDefaults.set(tmdbLanguageCode, forKey: CinuePreferenceKeys.tmdbLanguageCode)
        }

        if let episodeNotificationsEnabled = preferences.episodeNotificationsEnabled {
            userDefaults.set(episodeNotificationsEnabled, forKey: CinuePreferenceKeys.episodeNotificationsEnabled)
        }

        if let episodeNotificationLeadTimeSeconds = preferences.episodeNotificationLeadTimeSeconds {
            userDefaults.set(
                episodeNotificationLeadTimeSeconds,
                forKey: CinuePreferenceKeys.episodeNotificationLeadTimeSeconds
            )
        }
    }

    private func upsertTrackedItem(
        context: NSManagedObjectContext,
        cache: ImportLookupCache,
        localID: String,
        kindRaw: String,
        title: String,
        sortTitle: String?,
        tvdbID: Int?,
        tmdbID: Int?,
        imdbID: String?,
        statusRaw: String,
        watchCount: Int,
        watchedAt: Date?,
        isCollected: Bool,
        isFavorite: Bool,
        isHidden: Bool,
        userRating: Int?,
        notes: String?,
        createdAt: Date
    ) throws -> UpsertResult {
        let existing = cache.trackedItem(localID: localID, kindRaw: kindRaw, tvdbID: tvdbID, tmdbID: tmdbID, imdbID: imdbID)
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: "TrackedItem", into: context)

        if existing == nil {
            object.setValue(createdAt, forKey: "createdAt")
        }

        object.setValue(existing?.stringValue(forKey: "localID") ?? localID, forKey: "localID")
        object.setValue(kindRaw, forKey: "kindRaw")
        object.setValue(title, forKey: "title")
        object.setValue(sortTitle ?? title.localizedLowercase, forKey: "sortTitle")
        object.setOptionalInt(tvdbID, forKey: "tvdbID")
        object.setOptionalInt(tmdbID, forKey: "tmdbID")
        object.setValue(imdbID, forKey: "imdbID")
        object.setValue(statusRaw, forKey: "statusRaw")
        object.setValue(
            try exactInt32(max(0, watchCount), field: .trackedItemWatchCount),
            forKey: "watchCount"
        )
        object.setValue(watchedAt, forKey: "watchedAt")
        object.setValue(isCollected, forKey: "isCollected")
        object.setValue(isFavorite, forKey: "isFavorite")
        object.setValue(isHidden, forKey: "isHidden")
        object.setValue(
            try exactOptionalInt16(userRating, field: .trackedItemUserRating),
            forKey: "userRating"
        )
        object.setValue(notes, forKey: "notes")
        object.setValue(now(), forKey: "updatedAt")
        cache.storeTrackedItem(object)

        return existing == nil ? .inserted : .updated
    }

    private func upsertEpisodeState(
        context: NSManagedObjectContext,
        cache: ImportLookupCache,
        localID: String,
        showLocalID: String,
        seasonNumber: Int,
        episodeNumber: Int?,
        title: String?,
        tvdbID: Int?,
        tmdbID: Int?,
        statusRaw: String,
        watchCount: Int,
        watchedAt: Date?,
        isCollected: Bool,
        isSkipped: Bool,
        userRating: Int?,
        notes: String?,
        createdAt: Date
    ) throws -> UpsertResult {
        let existing = cache.object(entityName: "EpisodeState", localIDKey: "localID", localID: localID)
        let object = existing
            ?? NSEntityDescription.insertNewObject(forEntityName: "EpisodeState", into: context)
        let isInsert = existing == nil

        if isInsert {
            object.setValue(createdAt, forKey: "createdAt")
        }

        object.setValue(localID, forKey: "localID")
        object.setValue(showLocalID, forKey: "showLocalID")
        object.setValue(
            try exactInt32(seasonNumber, field: .episodeSeasonNumber),
            forKey: "seasonNumber"
        )
        object.setValue(
            try exactOptionalInt32(episodeNumber, field: .episodeNumber),
            forKey: "episodeNumber"
        )
        object.setValue(title, forKey: "title")
        object.setOptionalInt(tvdbID, forKey: "tvdbID")
        object.setOptionalInt(tmdbID, forKey: "tmdbID")
        object.setValue(statusRaw, forKey: "statusRaw")
        object.setValue(
            try exactInt32(max(0, watchCount), field: .episodeWatchCount),
            forKey: "watchCount"
        )
        object.setValue(watchedAt, forKey: "watchedAt")
        object.setValue(isCollected, forKey: "isCollected")
        object.setValue(isSkipped, forKey: "isSkipped")
        object.setValue(
            try exactOptionalInt16(userRating, field: .episodeUserRating),
            forKey: "userRating"
        )
        object.setValue(notes, forKey: "notes")
        object.setValue(now(), forKey: "updatedAt")
        cache.storeObject(object, entityName: "EpisodeState", localIDKey: "localID", localID: localID)

        return isInsert ? .inserted : .updated
    }

    private func upsertUserList(
        context: NSManagedObjectContext,
        cache: ImportLookupCache,
        localID: String,
        name: String,
        sortOrder: Int,
        createdAt: Date
    ) throws -> UpsertResult {
        let existing = cache.object(entityName: "UserList", localIDKey: "localID", localID: localID)
        let object = existing
            ?? NSEntityDescription.insertNewObject(forEntityName: "UserList", into: context)
        let isInsert = existing == nil

        if isInsert {
            object.setValue(createdAt, forKey: "createdAt")
        }

        object.setValue(localID, forKey: "localID")
        object.setValue(name, forKey: "name")
        object.setValue(
            try exactInt32(sortOrder, field: .userListSortOrder),
            forKey: "sortOrder"
        )
        object.setValue(now(), forKey: "updatedAt")
        cache.storeObject(object, entityName: "UserList", localIDKey: "localID", localID: localID)

        return isInsert ? .inserted : .updated
    }

    private func upsertUserListItem(
        context: NSManagedObjectContext,
        cache: ImportLookupCache,
        localID: String,
        listLocalID: String,
        itemLocalID: String?,
        externalID: String?,
        kindRaw: String,
        tvdbID: Int?,
        tmdbID: Int?,
        sortOrder: Int,
        createdAt: Date
    ) throws -> UpsertResult {
        let existing = cache.object(entityName: "UserListItem", localIDKey: "localID", localID: localID)
        let object = existing
            ?? NSEntityDescription.insertNewObject(forEntityName: "UserListItem", into: context)
        let isInsert = existing == nil

        if isInsert {
            object.setValue(createdAt, forKey: "createdAt")
        }

        object.setValue(localID, forKey: "localID")
        object.setValue(listLocalID, forKey: "listLocalID")
        object.setValue(itemLocalID, forKey: "itemLocalID")
        object.setValue(externalID, forKey: "externalID")
        object.setValue(kindRaw, forKey: "kindRaw")
        object.setOptionalInt(tvdbID, forKey: "tvdbID")
        object.setOptionalInt(tmdbID, forKey: "tmdbID")
        object.setValue(
            try exactInt32(sortOrder, field: .userListItemSortOrder),
            forKey: "sortOrder"
        )
        object.setValue(now(), forKey: "updatedAt")
        cache.storeObject(object, entityName: "UserListItem", localIDKey: "localID", localID: localID)

        return isInsert ? .inserted : .updated
    }

    private func upsertMetadataRecord(
        context: NSManagedObjectContext,
        cache: ImportLookupCache,
        cacheID: String,
        providerRaw: String,
        providerContentID: String,
        kindRaw: String,
        title: String,
        overview: String?,
        posterURLString: String?,
        backdropURLString: String?,
        releaseDate: Date?,
        sourceURLString: String?,
        rawJSON: Data?
    ) throws {
        let object = cache.object(entityName: "MetadataRecord", localIDKey: "cacheID", localID: cacheID)
            ?? NSEntityDescription.insertNewObject(forEntityName: "MetadataRecord", into: context)

        object.setValue(cacheID, forKey: "cacheID")
        object.setValue(providerRaw, forKey: "providerRaw")
        object.setValue(providerContentID, forKey: "providerContentID")
        object.setValue(kindRaw, forKey: "kindRaw")
        object.setValue(title, forKey: "title")
        object.setValue(overview, forKey: "overview")
        object.setValue(posterURLString, forKey: "posterURLString")
        object.setValue(backdropURLString, forKey: "backdropURLString")
        object.setValue(releaseDate, forKey: "releaseDate")
        object.setValue(sourceURLString, forKey: "sourceURLString")
        object.setValue("Imported from SeriesGuide backup.", forKey: "attributionText")
        object.setValue(rawJSON, forKey: "rawJSON")
        object.setValue(now(), forKey: "fetchedAt")
        object.setValue(Calendar.current.date(byAdding: .month, value: 6, to: now()), forKey: "expiresAt")
        cache.storeObject(object, entityName: "MetadataRecord", localIDKey: "cacheID", localID: cacheID)
    }

    private func exactInt32(_ value: Int, field: BackupIntegerField) throws -> Int32 {
        guard let converted = Int32(exactly: value) else {
            throw BackupImportError.integerOutOfRange(field: field, value: value)
        }
        return converted
    }

    private func exactOptionalInt32(
        _ value: Int?,
        field: BackupIntegerField
    ) throws -> Int32? {
        guard let value else { return nil }
        return try exactInt32(value, field: field)
    }

    private func exactOptionalInt16(
        _ value: Int?,
        field: BackupIntegerField
    ) throws -> Int16? {
        guard let value else { return nil }
        guard let converted = Int16(exactly: value) else {
            throw BackupImportError.integerOutOfRange(field: field, value: value)
        }
        return converted
    }

    private func addingWithoutOverflow(
        _ lhs: Int,
        _ rhs: Int,
        field: BackupIntegerField
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard result.overflow == false else {
            throw BackupImportError.integerOverflow(field: field)
        }
        return result.partialValue
    }

    private func totalEpisodePlays(for show: SeriesGuideShowBackup) throws -> Int {
        var total = 0

        for season in show.seasons ?? [] {
            for episode in season.episodes ?? [] {
                total = try addingWithoutOverflow(
                    total,
                    episode.importedPlayCount,
                    field: .totalEpisodePlays
                )
            }
        }

        return total
    }

    private func apply(_ result: UpsertResult, to summary: inout BackupImportSummary) {
        switch result {
        case .inserted:
            summary.importedItems += 1
        case .updated:
            summary.updatedItems += 1
        }
    }

    private func detectBackupKind(json: Any) throws -> BackupKind {
        if let object = json as? [String: Any] {
            if object["app"] as? String == "Cinue" || object["trackedItems"] != nil {
                return .cinue
            }

            throw BackupImportError.unrecognizedFormat
        }

        guard let array = json as? [Any] else {
            throw BackupImportError.invalidPayload
        }

        guard array.isEmpty == false else {
            throw BackupImportError.unrecognizedFormat
        }

        guard let objects = array as? [[String: Any]], let first = objects.first else {
            throw BackupImportError.invalidPayload
        }

        let allKeys = objects.reduce(into: Set<String>()) { keys, object in
            keys.formUnion(object.keys)
        }

        if allKeys.contains("list_id") || allKeys.contains("items") {
            return .seriesGuideLists
        }

        let hasMovieShape = allKeys.contains("in_watchlist") || allKeys.contains("released_utc_ms") || allKeys.contains("watched")

        if allKeys.contains("seasons") || (allKeys.contains("tvdb_id") && hasMovieShape == false) {
            return .seriesGuideShows
        }

        if hasMovieShape || first["imdb_id"] != nil || first["tmdb_id"] != nil {
            return .seriesGuideMovies
        }

        throw BackupImportError.unrecognizedFormat
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func date(milliseconds: Int64?) -> Date? {
        guard let milliseconds else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private static func iso8601Date(_ string: String?) -> Date? {
        guard let string else {
            return nil
        }

        return ISO8601DateFormatter().date(from: string)
    }

    private static func tmdbImageURLString(_ path: String?, size: TMDBArtworkSize) -> String? {
        guard let path, path.isEmpty == false else {
            return nil
        }

        if let candidate = URL(string: path), candidate.scheme != nil {
            return try? ArtworkURLPolicy.tmdb.canonicalURL(for: candidate).absoluteString
        }

        return TMDBArtworkURL.make(path: path, size: size)?.absoluteString
    }

    private static func tmdbSourceURLString(kind: MediaKind, tmdbID: Int?) -> String? {
        guard let tmdbID else {
            return nil
        }

        switch kind {
        case .show:
            return "https://www.themoviedb.org/tv/\(tmdbID)"
        case .movie:
            return "https://www.themoviedb.org/movie/\(tmdbID)"
        }
    }

    private static func tmdbEpisodeSourceURLString(showTMDBID: Int?, seasonNumber: Int?, episodeNumber: Int?) -> String? {
        guard let showTMDBID, let seasonNumber, let episodeNumber else {
            return nil
        }

        return "https://www.themoviedb.org/tv/\(showTMDBID)/season/\(seasonNumber)/episode/\(episodeNumber)"
    }

    private enum BackupKind {
        case cinue
        case seriesGuideShows
        case seriesGuideMovies
        case seriesGuideLists
    }

    private enum UpsertResult {
        case inserted
        case updated
    }
}

private struct BackupImportResult {
    let summary: BackupImportSummary
    let preferences: CinueBackupPreferences?
}

private final class ImportLookupCache {
    private var objectsByKey: [String: [String: NSManagedObject]] = [:]
    private var trackedByProviderKey: [String: NSManagedObject] = [:]

    init(context: NSManagedObjectContext) throws {
        try loadObjects(entityName: "TrackedItem", localIDKey: "localID", context: context)
        try loadObjects(entityName: "EpisodeState", localIDKey: "localID", context: context)
        try loadObjects(entityName: "UserList", localIDKey: "localID", context: context)
        try loadObjects(entityName: "UserListItem", localIDKey: "localID", context: context)
        try loadObjects(entityName: "MetadataRecord", localIDKey: "cacheID", context: context)

        if let trackedItems = objectsByKey[Self.cacheKey(entityName: "TrackedItem", localIDKey: "localID")] {
            for object in trackedItems.values {
                storeTrackedProviderKeys(object)
            }
        }
    }

    func trackedItem(localID: String, kindRaw: String, tvdbID: Int?, tmdbID: Int?, imdbID: String?) -> NSManagedObject? {
        if let object = object(entityName: "TrackedItem", localIDKey: "localID", localID: localID) {
            return object
        }

        if let tvdbID, let object = trackedByProviderKey[providerKey(kindRaw: kindRaw, provider: "tvdb", id: "\(tvdbID)")] {
            return object
        }

        if let tmdbID, let object = trackedByProviderKey[providerKey(kindRaw: kindRaw, provider: "tmdb", id: "\(tmdbID)")] {
            return object
        }

        if let imdbID, let object = trackedByProviderKey[providerKey(kindRaw: kindRaw, provider: "imdb", id: imdbID)] {
            return object
        }

        return nil
    }

    func storeTrackedItem(_ object: NSManagedObject) {
        let localID = object.stringValue(forKey: "localID")
        storeObject(object, entityName: "TrackedItem", localIDKey: "localID", localID: localID)
        storeTrackedProviderKeys(object)
    }

    func object(entityName: String, localIDKey: String, localID: String) -> NSManagedObject? {
        objectsByKey[Self.cacheKey(entityName: entityName, localIDKey: localIDKey)]?[localID]
    }

    func storeObject(_ object: NSManagedObject, entityName: String, localIDKey: String, localID: String) {
        guard localID.isEmpty == false else {
            return
        }

        let key = Self.cacheKey(entityName: entityName, localIDKey: localIDKey)
        objectsByKey[key, default: [:]][localID] = object
    }

    private func loadObjects(entityName: String, localIDKey: String, context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.returnsObjectsAsFaults = false
        let objects = try context.fetch(request)
        let key = Self.cacheKey(entityName: entityName, localIDKey: localIDKey)

        objectsByKey[key] = objects.reduce(into: [:]) { partialResult, object in
            let localID = object.stringValue(forKey: localIDKey)
            if localID.isEmpty == false {
                partialResult[localID] = object
            }
        }
    }

    private func storeTrackedProviderKeys(_ object: NSManagedObject) {
        let kindRaw = object.stringValue(forKey: "kindRaw")

        if let tvdbID = object.intValue(forKey: "tvdbID") {
            trackedByProviderKey[providerKey(kindRaw: kindRaw, provider: "tvdb", id: "\(tvdbID)")] = object
        }

        if let tmdbID = object.intValue(forKey: "tmdbID") {
            trackedByProviderKey[providerKey(kindRaw: kindRaw, provider: "tmdb", id: "\(tmdbID)")] = object
        }

        if let imdbID = object.value(forKey: "imdbID") as? String, imdbID.isEmpty == false {
            trackedByProviderKey[providerKey(kindRaw: kindRaw, provider: "imdb", id: imdbID)] = object
        }
    }

    private func providerKey(kindRaw: String, provider: String, id: String) -> String {
        "\(kindRaw):\(provider):\(id)"
    }

    private static func cacheKey(entityName: String, localIDKey: String) -> String {
        "\(entityName):\(localIDKey)"
    }
}

private extension SeriesGuideShowBackup {
    var localID: String {
        if let tvdbID {
            return "seriesguide:show:tvdb:\(tvdbID)"
        }

        if let tmdbID {
            return "seriesguide:show:tmdb:\(tmdbID)"
        }

        if let imdbID {
            return "seriesguide:show:imdb:\(imdbID)"
        }

        return UUID().uuidString
    }

    var watchedEpisodeCount: Int {
        seasons?
            .flatMap { $0.episodes ?? [] }
            .filter { $0.watched == true }
            .count ?? 0
    }

    var providerContentID: String {
        if let tmdbID {
            return "tmdb:\(tmdbID)"
        }

        if let tvdbID {
            return "tvdb:\(tvdbID)"
        }

        if let imdbID {
            return "imdb:\(imdbID)"
        }

        return localID
    }
}

private extension SeriesGuideEpisodeBackup {
    var importedPlayCount: Int {
        max(plays ?? (watched == true ? 1 : 0), 0)
    }

    var watchStatus: WatchStatus {
        if skipped == true {
            return .skipped
        }

        if collected == true {
            return .collected
        }

        if watched == true || importedPlayCount > 0 {
            return .watched
        }

        return .unwatched
    }

    func localID(showLocalID: String, seasonNumber: Int) -> String {
        if let tvdbID {
            return "seriesguide:episode:tvdb:\(tvdbID)"
        }

        if let tmdbID {
            return "seriesguide:episode:tmdb:\(tmdbID)"
        }

        if let episode {
            return "seriesguide:episode:\(showLocalID):s\(seasonNumber):e\(episode)"
        }

        return UUID().uuidString
    }

    var providerContentID: String {
        if let tmdbID {
            return "tmdb:\(tmdbID)"
        }

        if let tvdbID {
            return "tvdb:\(tvdbID)"
        }

        return UUID().uuidString
    }
}

private extension SeriesGuideMovieBackup {
    var localID: String {
        if let tmdbID {
            return "seriesguide:movie:tmdb:\(tmdbID)"
        }

        if let imdbID {
            return "seriesguide:movie:imdb:\(imdbID)"
        }

        return UUID().uuidString
    }

    var providerContentID: String {
        if let tmdbID {
            return "tmdb:\(tmdbID)"
        }

        if let imdbID {
            return "imdb:\(imdbID)"
        }

        return localID
    }
}

private extension SeriesGuideListBackup {
    var localID: String {
        if let listID, listID.isEmpty == false {
            return "seriesguide:list:\(listID)"
        }

        if let name, name.isEmpty == false {
            return "seriesguide:list:\(name)"
        }

        return UUID().uuidString
    }
}

private extension SeriesGuideListItemBackup {
    func mappedListItem(listLocalID: String, sortOrder: Int) -> MappedListItem {
        let kindRaw = type?.contains("movie") == true ? MediaKind.movie.rawValue : MediaKind.show.rawValue
        let parsedExternalID = externalID.flatMap(Int.init)
        let parsedTVDBID = (tvdbID ?? 0) > 0 ? tvdbID : nil
        let parsedTMDBID = type?.contains("tmdb") == true ? parsedExternalID : nil
        let localID = listItemID.map { "seriesguide:listitem:\($0)" }
            ?? "seriesguide:listitem:\(listLocalID):\(externalID ?? UUID().uuidString)"

        return MappedListItem(
            localID: localID,
            listLocalID: listLocalID,
            itemLocalID: nil,
            externalID: externalID,
            kindRaw: kindRaw,
            tvdbID: parsedTVDBID,
            tmdbID: parsedTMDBID,
            sortOrder: sortOrder
        )
    }
}

private struct MappedListItem {
    var localID: String
    var listLocalID: String
    var itemLocalID: String?
    var externalID: String?
    var kindRaw: String
    var tvdbID: Int?
    var tmdbID: Int?
    var sortOrder: Int
}

private extension NSManagedObject {
    func stringValue(forKey key: String) -> String {
        value(forKey: key) as? String ?? ""
    }

    func primitiveBoolValue(forKey key: String) -> Bool {
        value(forKey: key) as? Bool ?? false
    }

    func primitiveIntValue(forKey key: String) -> Int {
        if let number = value(forKey: key) as? NSNumber {
            return number.intValue
        }

        return value(forKey: key) as? Int ?? 0
    }

    func intValue(forKey key: String) -> Int? {
        guard let number = value(forKey: key) as? NSNumber else {
            return nil
        }

        return number.intValue
    }

    func dateValue(forKey key: String, fallback: Date) -> Date {
        value(forKey: key) as? Date ?? fallback
    }

    func setOptionalInt(_ value: Int?, forKey key: String) {
        if let value {
            setValue(value, forKey: key)
        } else {
            setValue(nil, forKey: key)
        }
    }
}
