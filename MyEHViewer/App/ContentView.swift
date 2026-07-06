import SwiftUI

/// Hosts the root tab navigation for search, library, and settings.
struct ContentView: View {
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var appNavigationStore = AppNavigationStore()
    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw = AppThemeMode.system.rawValue

    var body: some View {
        TabView(selection: $appNavigationStore.selectedTab) {
            SearchView()
                .tabItem {
                    Label(AppCopy.searchTitle, systemImage: "magnifyingglass")
                }
                .tag(ContentTab.search)

            NavigationStack {
                LibraryView()
            }
                .tabItem {
                    Label(AppCopy.libraryTitle, systemImage: "books.vertical")
                }
                .tag(ContentTab.library)

            SettingsView()
                .tabItem {
                    Label(AppCopy.settingsTitle, systemImage: "gearshape")
                }
                .tag(ContentTab.settings)
        }
        .environmentObject(libraryStore)
        .environmentObject(appNavigationStore)
        .preferredColorScheme(preferredColorScheme)
        .tint(.appAccent)
        .fullScreenCover(isPresented: readerPresentationBinding) {
            readerPresentation
        }
    }

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Bridges the optional reader route into a dismissible full-screen cover.
    private var readerPresentationBinding: Binding<Bool> {
        Binding {
            appNavigationStore.readerRoute != nil
        } set: { isPresented in
            if !isPresented {
                appNavigationStore.closeReader()
            }
        }
    }

    /// Presents the active reader session above the tab hierarchy.
    @ViewBuilder
    private var readerPresentation: some View {
        if let route = appNavigationStore.readerRoute {
            NavigationStack {
                ReaderView(
                    initialPageURL: route.initialPageURL,
                    pageLinks: route.pageLinks,
                    totalPageCount: route.totalPageCount,
                    onClose: {
                        appNavigationStore.closeReader()
                    }
                )
                .id(route.id)
            }
            .environmentObject(libraryStore)
            .environmentObject(appNavigationStore)
            .preferredColorScheme(preferredColorScheme)
            .tint(.appAccent)
        }
    }
}

/// Identifies top-level app tabs.
enum ContentTab: Hashable {
    case search
    case library
    case settings
}

/// Describes the currently active reader session.
struct ReaderRoute: Identifiable, Equatable {
    let id = UUID()
    let initialPageURL: URL
    let pageLinks: [EHGalleryPageLink]
    let totalPageCount: Int?
}

/// Coordinates top-level tab selection and reader sessions.
@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab = ContentTab.search
    @Published private(set) var readerRoute: ReaderRoute?

    /// Opens a full-screen reader with the requested image page.
    func openReader(initialPageURL: URL, pageLinks: [EHGalleryPageLink] = [], totalPageCount: Int? = nil) {
        readerRoute = ReaderRoute(initialPageURL: initialPageURL, pageLinks: pageLinks, totalPageCount: totalPageCount)
    }

    /// Closes the active reader session and returns to the previous tab.
    func closeReader() {
        readerRoute = nil
    }
}

extension Color {
    /// Returns the shared app accent color required by the light theme.
    static let appAccent = Color(red: 0.0, green: 168.0 / 255.0, blue: 1.0)
}

#Preview {
    ContentView()
}
