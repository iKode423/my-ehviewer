import SwiftUI

/// Displays the live search entry point and result list.
struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    private let embedsInNavigationStack: Bool
    private let searchesOnAppear: Bool
    private let chromeMode: SearchChromeMode
    private let navigationTitle: String?

    /// Creates a search view with an injectable view model for previews and tests.
    init(
        viewModel: SearchViewModel = SearchViewModel(),
        embedsInNavigationStack: Bool = true,
        searchesOnAppear: Bool = false,
        chromeMode: SearchChromeMode = .full,
        navigationTitle: String? = AppCopy.searchTitle
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.embedsInNavigationStack = embedsInNavigationStack
        self.searchesOnAppear = searchesOnAppear
        self.chromeMode = chromeMode
        self.navigationTitle = navigationTitle
    }

    var body: some View {
        if embedsInNavigationStack {
            NavigationStack {
                titledSearchContent
            }
        } else {
            titledSearchContent
        }
    }

    /// Adds a navigation title only when this search owns the navigation context.
    @ViewBuilder
    private var titledSearchContent: some View {
        if let navigationTitle {
            searchContent.navigationTitle(navigationTitle)
        } else {
            searchContent
        }
    }

    /// Composes the reusable search screen content.
    private var searchContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                searchControls
                content
                    .padding(.top, viewModel.results.isEmpty ? 16 : 8)
            }
            .padding(.bottom, 16)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if searchesOnAppear {
                await viewModel.searchIfNeeded()
            }
        }
    }

    /// Groups search controls inside the screen's single vertical scroll area.
    private var searchControls: some View {
        VStack(spacing: 0) {
            searchBar
                .padding([.horizontal, .top])

            if chromeMode == .full {
                sourcePicker
                    .padding(.horizontal)
                    .padding(.top, 8)

                recentQueries
                    .padding(.horizontal)
                    .padding(.top, 8)

                filterPanel
                    .padding(.horizontal)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Provides the first visible search control for the application shell.
    private var searchBar: some View {
        HStack(spacing: 12) {
            TextField(AppCopy.searchPlaceholder, text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit {
                    Task { await viewModel.search() }
                }

            Button {
                Task { await viewModel.search() }
            } label: {
                Label(AppCopy.searchButtonTitle, systemImage: "magnifyingglass")
            }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
        }
    }

    /// Lets the user browse the front page or the popular endpoint.
    private var sourcePicker: some View {
        Picker(AppCopy.searchSourceTitle, selection: $viewModel.source) {
            ForEach(EHSearchSource.allCases) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Shows locally saved search shortcuts.
    @ViewBuilder
    private var recentQueries: some View {
        if !viewModel.recentQueries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppCopy.searchRecentTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        viewModel.clearRecentQueries()
                    } label: {
                        Label(AppCopy.searchClearRecent, systemImage: "trash")
                    }
                    .font(.caption)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.recentQueries, id: \.self) { recentQuery in
                            Button {
                                Task { await viewModel.useRecentQuery(recentQuery) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text(recentQuery)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: 160)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
            }
        }
    }

    /// Shows category and advanced search controls that map to site query parameters.
    private var filterPanel: some View {
        DisclosureGroup(AppCopy.searchFiltersTitle) {
            VStack(alignment: .leading, spacing: 16) {
                filterActions
                categoryFilterGrid
                advancedFilters
            }
            .padding(.top, 12)
        }
    }

    /// Shows filter-level actions that do not change the search query.
    private var filterActions: some View {
        HStack {
            Spacer()

            Button {
                viewModel.resetFilters()
            } label: {
                Label(AppCopy.searchResetFilters, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.hasActiveFilters || viewModel.isLoading)
        }
    }

    /// Lets the user hide categories using the site's `f_cats` bitmask.
    private var categoryFilterGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppCopy.searchHiddenCategoriesTitle)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(EHGalleryCategory.allCases) { category in
                    Toggle(category.displayName, isOn: hiddenCategoryBinding(for: category))
                        .toggleStyle(.button)
                        .font(.caption)
                }
            }
        }
    }

    /// Shows advanced search options documented from the current site script.
    private var advancedFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppCopy.searchAdvancedTitle)
                .font(.subheadline.weight(.semibold))

            Toggle(AppCopy.searchBrowseExpunged, isOn: $viewModel.browseExpunged)
            Toggle(AppCopy.searchRequireTorrent, isOn: $viewModel.requireTorrent)

            HStack(spacing: 12) {
                TextField(AppCopy.searchMinimumPages, text: $viewModel.minimumPagesText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                TextField(AppCopy.searchMaximumPages, text: $viewModel.maximumPagesText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }

            Picker(AppCopy.searchMinimumRating, selection: $viewModel.minimumRating) {
                Text(AppCopy.searchAnyRating).tag(0)
                ForEach(2...5, id: \.self) { value in
                    Text("\(value) 星").tag(value)
                }
            }
            .pickerStyle(.segmented)

            Toggle(AppCopy.searchDisableLanguageFilter, isOn: $viewModel.disableLanguageFilter)
            Toggle(AppCopy.searchDisableUploaderFilter, isOn: $viewModel.disableUploaderFilter)
            Toggle(AppCopy.searchDisableTagFilter, isOn: $viewModel.disableTagFilter)
        }
        .font(.subheadline)
    }

    /// Displays loading, empty, error, and result list states.
    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.results.isEmpty {
            ContentUnavailableView(AppCopy.searchLoadingTitle, systemImage: "hourglass")
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if let errorMessage = viewModel.errorMessage, viewModel.results.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")

                Button {
                    Task { await viewModel.retry() }
                } label: {
                    Label(AppCopy.commonRetry, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if viewModel.hasSearched && viewModel.results.isEmpty {
            ContentUnavailableView(
                AppCopy.searchNoResultsTitle,
                systemImage: "magnifyingglass",
                description: Text(AppCopy.searchNoResultsMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if viewModel.results.isEmpty {
            ContentUnavailableView(
                AppCopy.searchEmptyTitle,
                systemImage: "magnifyingglass",
                description: Text(AppCopy.searchEmptyMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            resultList
        }
    }

    /// Shows parsed search results and pagination actions.
    private var resultList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.red.opacity(0.08))
            }

            ForEach(viewModel.results) { result in
                NavigationLink {
                    GalleryDetailView(result: result)
                } label: {
                    SearchResultRow(result: result)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 100)
            }

            paginationControls
                .padding(.horizontal)
        }
    }

    /// Shows previous and next page actions when available.
    private var paginationControls: some View {
        HStack {
            Button {
                Task { await viewModel.loadPreviousPage() }
            } label: {
                Label(AppCopy.searchPreviousPage, systemImage: "chevron.left")
            }
            .disabled(viewModel.previousPageURL == nil || viewModel.isLoading)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
            }

            Spacer()

            Button {
                Task { await viewModel.loadNextPage() }
            } label: {
                Label(AppCopy.searchNextPage, systemImage: "chevron.right")
            }
            .disabled(viewModel.nextPageURL == nil || viewModel.isLoading)
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 8)
    }

    /// Creates a binding for one category in the hidden category set.
    private func hiddenCategoryBinding(for category: EHGalleryCategory) -> Binding<Bool> {
        Binding {
            viewModel.excludedCategories.contains(category)
        } set: { isHidden in
            if isHidden {
                viewModel.excludedCategories.insert(category)
            } else {
                viewModel.excludedCategories.remove(category)
            }
        }
    }
}

/// Selects how much search chrome should be visible.
enum SearchChromeMode {
    case full
    case keywordOnly
}

#Preview {
    SearchView()
}
