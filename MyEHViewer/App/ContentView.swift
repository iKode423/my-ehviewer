import SwiftUI

/// Hosts the root tab navigation for search, reading, and settings.
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

            NavigationStack {
                readerTabContent
            }
                .tabItem {
                    Label(AppCopy.readerTitle, systemImage: "book.pages")
                }
                .tag(ContentTab.reader)

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
    }

    /// Shows the active reader session or the empty reader state.
    @ViewBuilder
    private var readerTabContent: some View {
        if let route = appNavigationStore.readerRoute {
            ReaderView(initialPageURL: route.initialPageURL, pageLinks: route.pageLinks, totalPageCount: route.totalPageCount)
                .id(route.id)
        } else {
            ReaderView()
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
}

/// Identifies top-level app tabs.
enum ContentTab: Hashable {
    case search
    case library
    case reader
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

    /// Opens the reader tab with the requested image page.
    func openReader(initialPageURL: URL, pageLinks: [EHGalleryPageLink] = [], totalPageCount: Int? = nil) {
        readerRoute = ReaderRoute(initialPageURL: initialPageURL, pageLinks: pageLinks, totalPageCount: totalPageCount)
        selectedTab = .reader
    }
}

extension Color {
    /// Returns the shared app accent color required by the light theme.
    static let appAccent = Color(red: 0.0, green: 168.0 / 255.0, blue: 1.0)
}

#Preview {
    ContentView()
}
