import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProviderSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(CinuePreferenceKeys.tmdbLanguageCode) private var tmdbLanguageCode = ""

    @State private var tmdbKey = ""
    @State private var tmdbCredential = ProviderCredentialSummary()
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Saved Credentials") {
                ProviderCredentialStatusRow(
                    providerName: "TMDB",
                    symbol: "film.stack.fill",
                    summary: tmdbCredential
                )
            }

            Section("TMDB") {
                credentialField(
                    placeholder: "Paste TMDB API key or read token",
                    text: $tmdbKey,
                    accessibilityLabel: "TMDB API key or read token"
                )

                HStack {
                    Button(tmdbCredential.isConfigured ? "Update Credential" : "Save Credential") {
                        save(tmdbKey, provider: .tmdb)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)

                    Button("Paste") {
                        pasteClipboard(into: $tmdbKey, label: "TMDB credential")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                    Spacer()

                    Button("Remove", role: .destructive) {
                        deleteTMDBKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(tmdbCredential.isConfigured == false)
                    .frame(minHeight: 44)
                }
            }

            Section("Localization") {
                TextField("Language code, e.g. en-US", text: $tmdbLanguageCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)

                LabeledContent("Active Language", value: CinuePreferences.tmdbLanguageCode)

                Text("Search, Discover, and metadata refresh requests use this TMDB language code. Leave it blank to use the device language.")
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                Text("Keys stay in this device's Keychain. Provider metadata remains separate from your watch history.")
                    .foregroundStyle(.secondary)

                Text("Cinue uses TMDB as its active metadata provider. TMDB accepts a v3 API key or a v4 read access token. TMDB cache must expire within 6 months, and attribution appears in Discover, detail screens, and About.")
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cinueBottomChromeScrollMargins()
        .task {
            loadStoredKeys()
        }
        .navigationTitle("Provider Keys")
        .cinueAutoDismissFeedback($statusMessage)
    }

    private func credentialField(
        placeholder: String,
        text: Binding<String>,
        accessibilityLabel: String
    ) -> some View {
        SecureField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .font(.body.monospaced())
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 48)
            .privacySensitive()
            .accessibilityLabel(accessibilityLabel)
    }

    private func loadStoredKeys() {
        do {
            tmdbCredential = ProviderCredentialSummary(value: try environment.keychain.read(account: providerAccount(.tmdb)))
            tmdbKey = ""
        } catch {
            statusMessage = "Could not read saved keys."
        }
    }

    private func save(_ value: String, provider: MetadataProviderID) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedValue.isEmpty == false else {
            statusMessage = "Enter a key before saving."
            return
        }

        do {
            try environment.keychain.save(trimmedValue, account: providerAccount(provider))
            setCredentialSummary(value: trimmedValue, provider: provider)
            clearDraft(for: provider)
            statusMessage = "\(providerDisplayName(provider)) credential saved."
        } catch {
            statusMessage = "Could not save key."
        }
    }

    private func pasteClipboard(into text: Binding<String>, label: String) {
        #if canImport(UIKit)
        let pastedValue = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard pastedValue.isEmpty == false else {
            statusMessage = "Clipboard is empty."
            return
        }

        text.wrappedValue = pastedValue
        statusMessage = "Pasted \(label)."
        #else
        statusMessage = "Clipboard paste is not available here."
        #endif
    }

    private func deleteTMDBKey() {
        delete(provider: .tmdb)
    }

    private func delete(provider: MetadataProviderID) {
        do {
            try environment.keychain.delete(account: providerAccount(provider))
            setCredentialSummary(value: nil, provider: provider)
            clearDraft(for: provider)
            statusMessage = "\(providerDisplayName(provider)) credential removed."
        } catch {
            statusMessage = "Could not remove key."
        }
    }

    private func setCredentialSummary(value: String?, provider: MetadataProviderID) {
        switch provider {
        case .tmdb:
            tmdbCredential = ProviderCredentialSummary(value: value)
        case .theTVDB:
            break
        case .tvmaze:
            break
        }
    }

    private func clearDraft(for provider: MetadataProviderID) {
        switch provider {
        case .tmdb:
            tmdbKey = ""
        case .theTVDB:
            break
        case .tvmaze:
            break
        }
    }

    private func providerDisplayName(_ provider: MetadataProviderID) -> String {
        switch provider {
        case .theTVDB:
            "TheTVDB"
        case .tmdb:
            "TMDB"
        case .tvmaze:
            "TVmaze"
        }
    }

    private func providerAccount(_ provider: MetadataProviderID) -> String {
        switch provider {
        case .theTVDB:
            "thetvdb.apiKey"
        case .tmdb:
            "tmdb.apiKey"
        case .tvmaze:
            "tvmaze.apiKey"
        }
    }
}

private struct ProviderCredentialStatusRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let providerName: String
    let symbol: String
    let summary: ProviderCredentialSummary

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            CinueIconTile(symbol: symbol, tone: .metadata, size: 32)

            VStack(alignment: .leading, spacing: CinueSpacing.xs) {
                Text(providerName)
                    .font(.body.weight(.semibold))

                Text(summary.maskedValue)
                    .font(.footnote.monospaced())
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: CinueSpacing.md)

            Text(summary.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTextColor)
                .padding(.horizontal, CinueSpacing.sm)
                .padding(.vertical, CinueSpacing.xs)
                .background(
                    Capsule()
                        .fill(statusBackgroundColor)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(providerName) \(summary.statusText). \(summary.maskedValue).")
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextSecondary
    }

    private var statusTextColor: Color {
        summary.isConfigured ? CinueColors.watchedGreen : secondaryTextColor
    }

    private var statusBackgroundColor: Color {
        if summary.isConfigured {
            return CinueColors.watchedGreen.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }

        return secondaryTextColor.opacity(colorScheme == .dark ? 0.14 : 0.10)
    }
}

#Preview {
    NavigationStack { ProviderSettingsView() }
}
