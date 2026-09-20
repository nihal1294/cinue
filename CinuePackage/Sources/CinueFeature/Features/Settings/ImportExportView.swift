import SwiftUI
import UniformTypeIdentifiers

struct ImportExportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var exportDocument = CinueBackupFile()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isImportInProgress = false
    @State private var statusMessage = CinueCopy.Settings.importExportIntro

    var body: some View {
        Form {
            Section("Cinue Backup") {
                Button {
                    prepareExport()
                } label: {
                    CinueSettingsRow(title: "Export Cinue Backup", symbol: "square.and.arrow.up.fill", tone: .importExport)
                }

                Button {
                    isImporting = true
                } label: {
                    CinueSettingsRow(title: "Import Backup File", symbol: "square.and.arrow.down.fill", tone: .importExport)
                }
                .disabled(isImportInProgress)
            }

            Section("SeriesGuide Migration") {
                Text(CinueCopy.Settings.importSourceHelp)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                if isImportInProgress {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(CinueCopy.Settings.importProgress)
                    }
                    .foregroundStyle(.secondary)
                }

                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .cinueBottomChromeScrollMargins()
        .navigationTitle("Import and Export")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename
        ) { result in
            switch result {
            case .success:
                statusMessage = CinueCopy.Settings.exportSuccess
            case .failure:
                statusMessage = CinueCopy.Settings.exportFailure
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
    }

    private var defaultExportFilename: String {
        "cinue-backup-\(Self.filenameDateFormatter.string(from: Date())).json"
    }

    private func prepareExport() {
        do {
            exportDocument = CinueBackupFile(data: try environment.backupService.exportCinueBackup())
            isExporting = true
            statusMessage = CinueCopy.Settings.exportPreparing
        } catch {
            statusMessage = "Could not prepare export."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            importBackup(from: url)
        } catch {
            statusMessage = CinueCopy.Settings.importFailure
        }
    }

    private func importBackup(from url: URL) {
        isImportInProgress = true
        statusMessage = CinueCopy.Settings.importStarted

        Task {
            do {
                let summary = try await environment.backupService.importBackupFile(at: url)
                statusMessage = summary.message
                await environment.refreshMetadataOnAppOpen()
            } catch {
                statusMessage = CinueCopy.Settings.importFailure
            }

            isImportInProgress = false
        }
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

private struct CinueBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data("{}".utf8)) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    NavigationStack {
        ImportExportView()
            .environment(AppEnvironment.preview())
    }
}
