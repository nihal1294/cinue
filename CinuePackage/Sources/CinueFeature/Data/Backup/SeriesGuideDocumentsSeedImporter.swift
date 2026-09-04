import Foundation

struct SeriesGuideDocumentsSeedImporter {
    let documentsDirectory: URL
    let backupService: BackupService

    func importAvailableBackups() async throws -> [BackupImportSummary] {
        let backupURLs = try Self.orderedBackupURLs(in: documentsDirectory)
        var summaries: [BackupImportSummary] = []

        for backupURL in backupURLs {
            let summary = try await backupService.importBackupFile(at: backupURL)
            summaries.append(summary)
        }

        return summaries
    }

    static func orderedBackupURLs(in directory: URL, fileManager: FileManager = .default) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { url in
                url.pathExtension.localizedCaseInsensitiveCompare("json") == .orderedSame
                    && url.lastPathComponent.hasPrefix("seriesguide-")
            }
            .sorted { lhs, rhs in
                let lhsPriority = importPriority(for: lhs.lastPathComponent)
                let rhsPriority = importPriority(for: rhs.lastPathComponent)

                if lhsPriority == rhsPriority {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }

                return lhsPriority < rhsPriority
            }
    }

    private static func importPriority(for filename: String) -> Int {
        if filename.hasPrefix("seriesguide-shows-") {
            return 0
        }

        if filename.hasPrefix("seriesguide-movies-") {
            return 1
        }

        if filename.hasPrefix("seriesguide-lists-") {
            return 2
        }

        return 3
    }
}
