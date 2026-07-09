import SwiftUI
import UIKit

/// Hosts the root tab navigation for search, library, and settings.
struct ContentView: View {
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var appNavigationStore = AppNavigationStore()
    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw = AppThemeMode.system.rawValue
    @AppStorage(AppAccentColor.storageKey) private var accentColorHex = AppAccentColor.defaultHex

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
                FavoriteImagesView()
            }
                .tabItem {
                    Label(AppCopy.libraryImageFavorites, systemImage: "heart")
                }
                .tag(ContentTab.imageFavorites)

            SettingsView()
                .tabItem {
                    Label(AppCopy.settingsTitle, systemImage: "gearshape")
                }
                .tag(ContentTab.settings)
        }
        .environmentObject(libraryStore)
        .environmentObject(appNavigationStore)
        .preferredColorScheme(preferredColorScheme)
        .accentColor(accentColor)
        .tint(accentColor)
        .fullScreenCover(isPresented: readerPresentationBinding) {
            readerPresentation
        }
        .onAppear {
            applyUIKitAccentColor(accentColor)
        }
        .onChange(of: accentColorHex) { _, _ in
            applyUIKitAccentColor(accentColor)
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

    private var accentColor: Color {
        AppAccentColor.color(from: accentColorHex)
    }

    /// Applies the SwiftUI accent to UIKit-backed controls that cache the window tint.
    private func applyUIKitAccentColor(_ color: Color) {
        let uiColor = UIColor(color)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                window.tintColor = uiColor
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
            .accentColor(accentColor)
            .tint(accentColor)
        }
    }
}

/// Identifies top-level app tabs.
enum ContentTab: Hashable {
    case search
    case library
    case imageFavorites
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

/// Stores and converts the user-selected app accent color.
enum AppAccentColor {
    static let storageKey = "App.accentColorHex"
    static let defaultHex = "#00A8FF"

    /// Converts a persisted hex string into a SwiftUI color.
    static func color(from hex: String) -> Color {
        guard let components = rgbComponents(from: hex) else {
            return Color(red: 0.0, green: 168.0 / 255.0, blue: 1.0)
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// Converts a SwiftUI color into a stable uppercase hex string.
    static func hex(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return defaultHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// Parses a six-digit RGB hex string.
    private static func rgbComponents(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHex = trimmedHex.hasPrefix("#") ? String(trimmedHex.dropFirst()) : trimmedHex
        guard normalizedHex.count == 6, let value = Int(normalizedHex, radix: 16) else {
            return nil
        }
        return (
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

#Preview {
    ContentView()
}
