import SwiftUI

/// Displays the live search entry point and result list.
struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @AppStorage(ContentSite.storageKey) private var contentSiteRaw = ContentSite.eHentai.rawValue
    private let embedsInNavigationStack: Bool
    private let searchesOnAppear: Bool
    private let chromeMode: SearchChromeMode
    private let navigationTitle: String?
    private let followsAppContentSite: Bool
    @State private var pageJumpText = ""

    /// Creates a search view with an injectable view model for previews and tests.
    init(
        viewModel: SearchViewModel = SearchViewModel(),
        embedsInNavigationStack: Bool = true,
        searchesOnAppear: Bool = false,
        chromeMode: SearchChromeMode = .full,
        navigationTitle: String? = AppCopy.searchTitle,
        followsAppContentSite: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.embedsInNavigationStack = embedsInNavigationStack
        self.searchesOnAppear = searchesOnAppear
        self.chromeMode = chromeMode
        self.navigationTitle = navigationTitle
        self.followsAppContentSite = followsAppContentSite
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
        .overlay {
            if viewModel.isLoading {
                SearchLoadingOverlay()
            }
        }
        .task {
            syncContentSiteIfNeeded()
            if searchesOnAppear {
                await viewModel.searchIfNeeded()
                syncPageJumpText()
            }
        }
        .onChange(of: contentSiteRaw) { _, _ in
            syncContentSiteIfNeeded()
            syncPageJumpText()
        }
        .onChange(of: viewModel.currentPageNumber) { _, _ in
            syncPageJumpText()
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

                if viewModel.site == .eHentai {
                    filterPanel
                        .padding(.horizontal)
                        .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Provides the first visible search control for the application shell.
    private var searchBar: some View {
        HStack(spacing: 10) {
            TextField(AppCopy.searchPlaceholder, text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit {
                    Task { await performSearch() }
                }

            Button {
                Task { await performSearch() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.5 : 1)
            .accessibilityLabel(AppCopy.searchButtonTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Lets the user browse the front page or the popular endpoint.
    private var sourcePicker: some View {
        Picker(AppCopy.searchSourceTitle, selection: $viewModel.source) {
            ForEach(viewModel.availableSources) { source in
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
                                Task {
                                    await viewModel.useRecentQuery(recentQuery)
                                    syncPageJumpText()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .imageScale(.small)
                                    Text(recentQuery)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: 130)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading)
                            .opacity(viewModel.isLoading ? 0.5 : 1)
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
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.hasActiveFilters || viewModel.isLoading)
            .opacity((!viewModel.hasActiveFilters || viewModel.isLoading) ? 0.45 : 1)
            .accessibilityLabel(AppCopy.searchResetFilters)
        }
    }

    /// Lets the user hide categories using the site's `f_cats` bitmask.
    private var categoryFilterGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppCopy.searchHiddenCategoriesTitle)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(EHGalleryCategory.allCases) { category in
                    let isHidden = viewModel.excludedCategories.contains(category)

                    Button {
                        if isHidden {
                            viewModel.excludedCategories.remove(category)
                        } else {
                            viewModel.excludedCategories.insert(category)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .imageScale(.small)
                            Text(category.displayName)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .overlay(
                            Capsule()
                                .stroke(isHidden ? Color.gray.opacity(0.45) : Color.accentColor.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isHidden ? .secondary : .primary)
                    .opacity(isHidden ? 0.5 : 1)
                    .accessibilityValue(isHidden ? "已隐藏" : "未隐藏")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shows advanced search options documented from the current site script.
    private var advancedFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppCopy.searchAdvancedTitle)
                .font(.subheadline.weight(.semibold))

            compactFilterToggle(AppCopy.searchBrowseExpunged, isOn: $viewModel.browseExpunged)
            compactFilterToggle(AppCopy.searchRequireTorrent, isOn: $viewModel.requireTorrent)

            HStack(spacing: 10) {
                TextField(AppCopy.searchMinimumPages, text: $viewModel.minimumPagesText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 0, maxWidth: .infinity)

                TextField(AppCopy.searchMaximumPages, text: $viewModel.maximumPagesText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            Picker(AppCopy.searchMinimumRating, selection: $viewModel.minimumRating) {
                Text(AppCopy.searchAnyRating).tag(0)
                ForEach(2...5, id: \.self) { value in
                    Text("\(value) 星").tag(value)
                }
            }
            .pickerStyle(.menu)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(AppCopy.searchMinimumRating)

            compactFilterToggle(AppCopy.searchDisableLanguageFilter, isOn: $viewModel.disableLanguageFilter)
            compactFilterToggle(AppCopy.searchDisableUploaderFilter, isOn: $viewModel.disableUploaderFilter)
            compactFilterToggle(AppCopy.searchDisableTagFilter, isOn: $viewModel.disableTagFilter)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Builds a compact left-aligned boolean filter row without a trailing switch.
    private func compactFilterToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .imageScale(.small)
                    .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "已开启" : "已关闭")
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
        HStack(spacing: 6) {
            Button {
                Task {
                    await viewModel.loadPreviousPage()
                    syncPageJumpText()
                }
            } label: {
                Label(AppCopy.searchPreviousPage, systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .disabled(viewModel.previousPageURL == nil || viewModel.isLoading)
            .accessibilityLabel(AppCopy.searchPreviousPage)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 22, height: 22)
            }

            Spacer()

            pageJumpControl

            Spacer()

            Button {
                Task {
                    await viewModel.loadNextPage()
                    syncPageJumpText()
                }
            } label: {
                Label(AppCopy.searchNextPage, systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .disabled(viewModel.nextPageURL == nil || viewModel.isLoading)
            .accessibilityLabel(AppCopy.searchNextPage)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    /// Lets the user jump directly to a numbered result page.
    private var pageJumpControl: some View {
        HStack(spacing: 3) {
            TextField(AppCopy.searchPageField, text: $pageJumpText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
                .frame(width: 32)
                .submitLabel(.go)
                .onSubmit {
                    Task { await loadJumpPage() }
                }

            Button {
                Task { await loadJumpPage() }
            } label: {
                Label(AppCopy.searchJumpPage, systemImage: "arrow.right.to.line")
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .disabled(jumpPageNumber == nil || viewModel.isLoading)
            .accessibilityLabel(AppCopy.searchJumpPage)
        }
        .frame(minHeight: 44)
    }

    /// Parses and loads the page number entered in the pagination controls.
    private func loadJumpPage() async {
        guard let pageNumber = jumpPageNumber else { return }
        await viewModel.loadPage(number: pageNumber)
        syncPageJumpText()
    }

    /// Runs a new search and updates the visible page number field.
    private func performSearch() async {
        await viewModel.search()
        syncPageJumpText()
    }

    /// Keeps the jump field aligned with the last successfully loaded page.
    private func syncPageJumpText() {
        pageJumpText = String(viewModel.currentPageNumber)
    }

    /// Applies the global site selection when this screen follows app settings.
    private func syncContentSiteIfNeeded() {
        guard followsAppContentSite else { return }
        viewModel.setSite(currentSite)
    }

    /// Returns the positive page number entered by the user.
    private var jumpPageNumber: Int? {
        let trimmedText = pageJumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmedText), pageNumber > 0 else { return nil }
        return pageNumber
    }

    /// Resolves the app-wide content site selected in settings.
    private var currentSite: ContentSite {
        ContentSite.resolved(rawValue: contentSiteRaw)
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

/// Presents a modal loading hint over the search screen.
private struct SearchLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            ProgressView(AppCopy.searchLoadingTitle)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(radius: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SearchView()
}
