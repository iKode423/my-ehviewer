import SwiftUI

/// Shows local data controls and reader-related preferences.
struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var siteCookieStore = SiteCookieStore.shared
    @AppStorage(ReaderFitMode.storageKey) private var fitModeRaw = ReaderFitMode.fitPage.rawValue
    @AppStorage(ReaderZoomLevel.storageKey) private var zoomLevelRaw = ReaderZoomLevel.x1.rawValue
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    @State private var cookieInput = ""
    @State private var showsClearConfirmation = false
    @State private var showsCookieClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                readerPreferencesSection
                siteAccessSection
                localDataSection
                cachePolicySection
            }
            .navigationTitle(AppCopy.settingsTitle)
            .onAppear {
                cookieInput = siteCookieStore.cookieHeader
            }
            .confirmationDialog(
                AppCopy.settingsClearConfirmationTitle,
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsClearConfirm, role: .destructive) {
                    libraryStore.removeAll()
                }
            } message: {
                Text(AppCopy.settingsClearConfirmationMessage)
            }
            .confirmationDialog(
                AppCopy.settingsCookieClearTitle,
                isPresented: $showsCookieClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsCookieClearConfirm, role: .destructive) {
                    siteCookieStore.clearCookieHeader()
                    cookieInput = ""
                }
            }
        }
    }

    /// Shows reader display preferences shared with ReaderView.
    private var readerPreferencesSection: some View {
        Section(AppCopy.settingsReaderPreferencesTitle) {
            Picker(AppCopy.readerDisplayMode, selection: $fitModeRaw) {
                ForEach(ReaderFitMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Picker(AppCopy.readerZoomMode, selection: $zoomLevelRaw) {
                ForEach(ReaderZoomLevel.allCases) { level in
                    Text(level.title).tag(level.rawValue)
                }
            }

            Picker(AppCopy.readerBackgroundMode, selection: $backgroundModeRaw) {
                ForEach(ReaderBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        }
    }

    /// Shows account cookie controls used by network requests.
    private var siteAccessSection: some View {
        Section(AppCopy.settingsSiteAccessTitle) {
            Label(
                siteCookieStore.hasCookieHeader ? AppCopy.settingsCookieConfigured : AppCopy.settingsCookieMissing,
                systemImage: siteCookieStore.hasCookieHeader ? "checkmark.seal" : "exclamationmark.triangle"
            )

            SecureField(AppCopy.settingsCookieField, text: $cookieInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                siteCookieStore.saveCookieHeader(cookieInput)
                cookieInput = siteCookieStore.cookieHeader
            } label: {
                Label(AppCopy.settingsCookieSave, systemImage: "key")
            }
            .disabled(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                showsCookieClearConfirmation = true
            } label: {
                Label(AppCopy.settingsCookieClear, systemImage: "trash")
            }
            .disabled(!siteCookieStore.hasCookieHeader)

            if let errorMessage = siteCookieStore.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    /// Shows local library counters and destructive cleanup controls.
    private var localDataSection: some View {
        Section(AppCopy.settingsLocalDataTitle) {
            Label(String(format: AppCopy.settingsHistoryCount, String(libraryStore.history.count)), systemImage: "clock")
            Label(String(format: AppCopy.settingsFavoritesCount, String(libraryStore.favorites.count)), systemImage: "star")

            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Label(AppCopy.settingsClearLocalData, systemImage: "trash")
            }
            .disabled(libraryStore.history.isEmpty && libraryStore.favorites.isEmpty)
        }
    }

    /// Explains the current remote-content cache policy.
    private var cachePolicySection: some View {
        Section(AppCopy.settingsCacheNoteTitle) {
            Label(AppCopy.settingsCacheNoteMessage, systemImage: "internaldrive")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(LibraryStore())
}
