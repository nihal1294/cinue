import Foundation

struct BackupImportPolicy: Equatable, Sendable {
    static let standard = BackupImportPolicy(
        maximumFileBytes: 16 * 1_024 * 1_024,
        maximumTopLevelRecords: 10_000,
        maximumNestedEpisodes: 50_000,
        maximumAggregateRecords: 100_000,
        maximumStringUTF8Bytes: 64 * 1_024,
        maximumJSONNestingDepth: 16
    )

    let maximumFileBytes: Int
    let maximumTopLevelRecords: Int
    let maximumNestedEpisodes: Int
    let maximumAggregateRecords: Int
    let maximumStringUTF8Bytes: Int
    let maximumJSONNestingDepth: Int
}

enum BackupIntegerField: String, Equatable, Sendable {
    case trackedItemWatchCount
    case trackedItemUserRating
    case episodeSeasonNumber
    case episodeNumber
    case episodeWatchCount
    case episodeUserRating
    case userListSortOrder
    case userListItemSortOrder
    case totalEpisodePlays
}

enum BackupImportError: Error, Equatable {
    case unrecognizedFormat
    case malformedJSON
    case invalidPayload
    case fileTooLarge(actualBytes: Int, maximumBytes: Int)
    case topLevelRecordLimitExceeded(actual: Int, maximum: Int)
    case nestedEpisodeLimitExceeded(actual: Int, maximum: Int)
    case aggregateRecordLimitExceeded(actual: Int, maximum: Int)
    case stringLimitExceeded(actualUTF8Bytes: Int, maximumUTF8Bytes: Int)
    case nestingLimitExceeded(actualDepth: Int, maximumDepth: Int)
    case integerOutOfRange(field: BackupIntegerField, value: Int)
    case integerOverflow(field: BackupIntegerField)
}

struct PreparedSerializedJSON {
    let root: Any
    let foundationData: Data
}

struct BackupImportValidator {
    let policy: BackupImportPolicy

    func validateFileByteCount(_ byteCount: Int) throws {
        guard byteCount <= policy.maximumFileBytes else {
            throw BackupImportError.fileTooLarge(
                actualBytes: byteCount,
                maximumBytes: policy.maximumFileBytes
            )
        }
    }

    func validateSerializedJSON(_ data: Data) throws {
        _ = try prepareAndValidateSerializedJSON(data)
    }

    func prepareAndValidateSerializedJSON(_ data: Data) throws -> PreparedSerializedJSON {
        let foundationData = try JSONNestingScanner(policy: policy)
            .foundationCompatibleData(from: data)

        let root: Any

        do {
            root = try JSONSerialization.jsonObject(with: foundationData, options: [.fragmentsAllowed])
        } catch {
            throw BackupImportError.malformedJSON
        }

        try validateSerializedJSONRoot(root)
        return PreparedSerializedJSON(root: root, foundationData: foundationData)
    }

    private func validateSerializedJSONRoot(_ root: Any) throws {
        var stack: [(value: Any, depth: Int)] = [(root, 1)]

        while let entry = stack.popLast() {
            switch entry.value {
            case let dictionary as [String: Any]:
                try validateNestingDepth(entry.depth)

                for (key, value) in dictionary {
                    try validate(string: key)
                    stack.append((value, entry.depth + 1))
                }
            case let array as [Any]:
                try validateNestingDepth(entry.depth)

                if entry.depth == 1 {
                    try validateTopLevelRecordCount(array.count)
                }

                for value in array {
                    stack.append((value, entry.depth + 1))
                }
            case let string as String:
                try validate(string: string)
            default:
                break
            }
        }
    }

    func validate(_ document: CinueBackupDocument) throws {
        try validateTopLevelRecordCount(document.trackedItems.count)
        try validateTopLevelRecordCount(document.episodeStates.count)
        try validateTopLevelRecordCount(document.lists.count)
        try validateTopLevelRecordCount(document.listItems.count)

        var aggregateRecords = 0
        aggregateRecords = try addingRecordCount(aggregateRecords, document.trackedItems.count)
        aggregateRecords = try addingRecordCount(aggregateRecords, document.episodeStates.count)
        aggregateRecords = try addingRecordCount(aggregateRecords, document.lists.count)
        _ = try addingRecordCount(aggregateRecords, document.listItems.count)

        try validate(string: document.app)

        for item in document.trackedItems {
            try validate(strings: [
                item.localID,
                item.kindRaw,
                item.title,
                item.sortTitle,
                item.imdbID,
                item.statusRaw,
                item.notes
            ])
            try validateInt32(max(0, item.watchCount), field: .trackedItemWatchCount)
            try validateOptionalInt16(item.userRating, field: .trackedItemUserRating)
        }

        for episode in document.episodeStates {
            try validate(strings: [
                episode.localID,
                episode.showLocalID,
                episode.title,
                episode.statusRaw,
                episode.notes
            ])
            try validateInt32(episode.seasonNumber, field: .episodeSeasonNumber)
            try validateOptionalInt32(episode.episodeNumber, field: .episodeNumber)
            try validateInt32(max(0, episode.watchCount), field: .episodeWatchCount)
            try validateOptionalInt16(episode.userRating, field: .episodeUserRating)
        }

        for list in document.lists {
            try validate(strings: [list.localID, list.name])
            try validateInt32(list.sortOrder, field: .userListSortOrder)
        }

        for item in document.listItems {
            try validate(strings: [
                item.localID,
                item.listLocalID,
                item.itemLocalID,
                item.externalID,
                item.kindRaw
            ])
            try validateInt32(item.sortOrder, field: .userListItemSortOrder)
        }

        if let preferences = document.preferences {
            try validate(strings: [
                preferences.appearanceModeRaw,
                preferences.tmdbLanguageCode
            ])
        }
    }

    func validate(_ shows: [SeriesGuideShowBackup]) throws {
        try validateTopLevelRecordCount(shows.count)

        var aggregateRecords = 0
        var nestedEpisodes = 0

        for show in shows {
            aggregateRecords = try addingRecordCount(aggregateRecords, 1)
            try validate(strings: [
                show.imdbID,
                show.title,
                show.overview,
                show.poster,
                show.firstAired,
                show.status,
                show.network,
                show.userNote
            ])
            try validateOptionalInt16(show.ratingUser, field: .trackedItemUserRating)

            var totalEpisodePlays = 0
            for season in show.seasons ?? [] {
                for episode in season.episodes ?? [] {
                    totalEpisodePlays = try addingWithoutOverflow(
                        totalEpisodePlays,
                        max(episode.plays ?? (episode.watched == true ? 1 : 0), 0),
                        field: .totalEpisodePlays
                    )
                }
            }
            try validateInt32(totalEpisodePlays, field: .trackedItemWatchCount)

            for season in show.seasons ?? [] {
                aggregateRecords = try addingRecordCount(aggregateRecords, 1)
                try validate(string: season.tmdbID)
                try validateInt32(season.season ?? 0, field: .episodeSeasonNumber)

                for episode in season.episodes ?? [] {
                    aggregateRecords = try addingRecordCount(aggregateRecords, 1)
                    nestedEpisodes = try addingNestedEpisodeCount(nestedEpisodes)
                    try validate(strings: [
                        episode.title,
                        episode.overview,
                        episode.image
                    ])
                    try validateOptionalInt32(episode.episode, field: .episodeNumber)
                    try validateInt32(
                        max(episode.plays ?? (episode.watched == true ? 1 : 0), 0),
                        field: .episodeWatchCount
                    )
                }
            }
        }
    }

    func validate(_ movies: [SeriesGuideMovieBackup]) throws {
        try validateTopLevelRecordCount(movies.count)

        var aggregateRecords = 0
        for movie in movies {
            aggregateRecords = try addingRecordCount(aggregateRecords, 1)
            try validate(strings: [
                movie.imdbID,
                movie.title,
                movie.poster,
                movie.overview
            ])
            try validateInt32(
                max(movie.plays ?? (movie.watched == true ? 1 : 0), 0),
                field: .trackedItemWatchCount
            )
        }
    }

    func validate(_ lists: [SeriesGuideListBackup]) throws {
        try validateTopLevelRecordCount(lists.count)

        var aggregateRecords = 0
        for list in lists {
            aggregateRecords = try addingRecordCount(aggregateRecords, 1)
            try validate(strings: [list.listID, list.name])
            try validateInt32(list.order ?? 0, field: .userListSortOrder)

            for (index, item) in (list.items ?? []).enumerated() {
                aggregateRecords = try addingRecordCount(aggregateRecords, 1)
                try validate(strings: [
                    item.externalID,
                    item.listItemID,
                    item.type
                ])
                try validateInt32(index, field: .userListItemSortOrder)
            }
        }
    }

    private func validateTopLevelRecordCount(_ count: Int) throws {
        guard count <= policy.maximumTopLevelRecords else {
            throw BackupImportError.topLevelRecordLimitExceeded(
                actual: count,
                maximum: policy.maximumTopLevelRecords
            )
        }
    }

    private func validateNestingDepth(_ depth: Int) throws {
        guard depth <= policy.maximumJSONNestingDepth else {
            throw BackupImportError.nestingLimitExceeded(
                actualDepth: depth,
                maximumDepth: policy.maximumJSONNestingDepth
            )
        }
    }

    private func validate(strings: [String?]) throws {
        for string in strings {
            try validate(string: string)
        }
    }

    private func validate(string: String?) throws {
        guard let string else {
            return
        }

        try validate(string: string)
    }

    private func validate(string: String) throws {
        let byteCount = string.utf8.count
        guard byteCount <= policy.maximumStringUTF8Bytes else {
            throw BackupImportError.stringLimitExceeded(
                actualUTF8Bytes: byteCount,
                maximumUTF8Bytes: policy.maximumStringUTF8Bytes
            )
        }
    }

    private func addingRecordCount(_ current: Int, _ added: Int) throws -> Int {
        let result = current.addingReportingOverflow(added)
        guard result.overflow == false else {
            throw BackupImportError.aggregateRecordLimitExceeded(
                actual: Int.max,
                maximum: policy.maximumAggregateRecords
            )
        }

        guard result.partialValue <= policy.maximumAggregateRecords else {
            throw BackupImportError.aggregateRecordLimitExceeded(
                actual: result.partialValue,
                maximum: policy.maximumAggregateRecords
            )
        }

        return result.partialValue
    }

    private func addingNestedEpisodeCount(_ current: Int) throws -> Int {
        let result = current.addingReportingOverflow(1)
        guard result.overflow == false else {
            throw BackupImportError.nestedEpisodeLimitExceeded(
                actual: Int.max,
                maximum: policy.maximumNestedEpisodes
            )
        }

        guard result.partialValue <= policy.maximumNestedEpisodes else {
            throw BackupImportError.nestedEpisodeLimitExceeded(
                actual: result.partialValue,
                maximum: policy.maximumNestedEpisodes
            )
        }

        return result.partialValue
    }

    private func validateInt32(_ value: Int, field: BackupIntegerField) throws {
        guard Int32(exactly: value) != nil else {
            throw BackupImportError.integerOutOfRange(field: field, value: value)
        }
    }

    private func validateOptionalInt32(_ value: Int?, field: BackupIntegerField) throws {
        guard let value else {
            return
        }

        try validateInt32(value, field: field)
    }

    private func validateOptionalInt16(_ value: Int?, field: BackupIntegerField) throws {
        guard let value else {
            return
        }

        guard Int16(exactly: value) != nil else {
            throw BackupImportError.integerOutOfRange(field: field, value: value)
        }
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
}
