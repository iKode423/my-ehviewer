import SwiftUI

/// Shows local data controls and reader-related preferences.
struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var showsClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                localDataSection
                cachePolicySection
            }
            .navigationTitle(AppCopy.settingsTitle)
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
