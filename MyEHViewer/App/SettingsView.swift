import SwiftUI

/// Shows application preferences that will be implemented after the core reader flow.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                AppCopy.settingsTitle,
                systemImage: "gearshape",
                description: Text(AppCopy.settingsMessage)
            )
            .navigationTitle(AppCopy.settingsTitle)
        }
    }
}

#Preview {
    SettingsView()
}

