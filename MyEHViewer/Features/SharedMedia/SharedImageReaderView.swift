import SwiftUI

/// Reads persistent shared images with the same tap, swipe, and favorite flow as gallery pages.
struct SharedImageReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SharedMediaStore
    @AppStorage(ReaderFitMode.storageKey) private var fitModeRaw = ReaderFitMode.fitPage.rawValue
    @AppStorage(ReaderZoomLevel.storageKey) private var zoomLevelRaw = ReaderZoomLevel.x1.rawValue
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    let records: [SharedMediaRecord]
    let initialRecordID: UUID
    @State private var currentIndex: Int
    @State private var showsChrome = true
    @State private var showsPageGridSheet = false
    @State private var showsPageJumpSheet = false
    @State private var pageJumpText = ""
    @State private var persistedPinchScale: CGFloat = 1
    @GestureState private var transientPinchScale: CGFloat = 1

    /// Creates a local reader positioned at the selected shared image.
    init(records: [SharedMediaRecord], initialRecordID: UUID) {
        self.records = records
        self.initialRecordID = initialRecordID
        _currentIndex = State(initialValue: records.firstIndex(where: { $0.id == initialRecordID }) ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .overlay {
            if currentRecord != nil, showsChrome {
                readerChromeOverlay
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: showsChrome)
        .background(readerBackground.ignoresSafeArea())
        .navigationTitle(AppCopy.readerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(readerChromeVisibility, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showsChrome)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label(AppCopy.readerBack, systemImage: "chevron.left")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                favoriteButton
                ReaderDisplayMenu(
                    fitModeRaw: $fitModeRaw,
                    zoomLevelRaw: $zoomLevelRaw,
                    backgroundModeRaw: $backgroundModeRaw,
                    canResetZoom: zoomLevel != .x1 || persistedPinchScale != 1,
                    resetZoom: resetReaderZoom
                )
            }
        }
        .sheet(isPresented: $showsPageJumpSheet) { pageJumpSheet }
        .sheet(isPresented: $showsPageGridSheet) { pageGridSheet }
        .onChange(of: currentIndex) { _, _ in resetTransientReaderState() }
    }

    private var currentRecord: SharedMediaRecord? {
        guard records.indices.contains(currentIndex) else { return nil }
        return store.records.first(where: { $0.id == records[currentIndex].id }) ?? records[currentIndex]
    }

    private var fitMode: ReaderFitMode {
        ReaderFitMode(rawValue: fitModeRaw) ?? .fitPage
    }

    private var zoomLevel: ReaderZoomLevel {
        ReaderZoomLevel.resolved(rawValue: zoomLevelRaw)
    }

    private var backgroundMode: ReaderBackgroundMode {
        ReaderBackgroundMode(rawValue: backgroundModeRaw) ?? .system
    }

    private var readerChromeVisibility: Visibility {
        showsChrome ? .visible : .hidden
    }

    private var activePinchScale: CGFloat {
        min(max(persistedPinchScale * transientPinchScale, 1), 4)
    }

    private var visibleZoomScale: CGFloat {
        min(CGFloat(zoomLevel.rawValue) * activePinchScale, 4)
    }

    private var visibleZoomTitle: String {
        "\(Int((visibleZoomScale * 100).rounded()))%"
    }

    private var pageJumpNumber: Int? {
        Int(pageJumpText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSubmitPageJump: Bool {
        guard let pageJumpNumber else { return false }
        return records.indices.contains(pageJumpNumber - 1)
    }

    private var readerBackground: Color {
        switch backgroundMode {
        case .system: Color(uiColor: .systemBackground)
        case .dark: .black
        case .paper: Color(red: 0.96, green: 0.93, blue: 0.86)
        }
    }

    private var readerForegroundStyle: Color {
        switch backgroundMode {
        case .dark: .white
        case .system, .paper: .primary
        }
    }

    @ViewBuilder
    private var content: some View {
        if let currentRecord {
            readerContent(for: currentRecord)
        } else {
            ContentUnavailableView(AppCopy.sharedMediaEmptyTitle, systemImage: "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Shows the current shared image and reader chrome.
    private func readerContent(for record: SharedMediaRecord) -> some View {
        GeometryReader { geometry in
            readerImageStage(for: record, geometry: geometry)
        }
        .ignoresSafeArea()
    }

    /// Shows the local image with the same fit and zoom behavior as gallery reading.
    private func readerImageStage(for record: SharedMediaRecord, geometry: GeometryProxy) -> some View {
        ScrollView([.vertical, .horizontal], showsIndicators: showsChrome) {
            HStack {
                Spacer(minLength: 0)

                SharedLocalImageView(url: store.fileURL(for: record))
                    .frame(width: readerImageWidth(availableWidth: geometry.size.width))
                    .contentShape(Rectangle())

                Spacer(minLength: 0)
            }
            .padding(fitMode == .fitPage ? 16 : 0)
            .frame(
                minWidth: geometry.size.width,
                minHeight: ReaderViewportLayout.fullScreenHeight,
                alignment: .center
            )
        }
        .background(readerBackground)
        .contentShape(Rectangle())
        .simultaneousGesture(readerTapGesture(in: geometry.size))
        .simultaneousGesture(readerPinchGesture)
        .simultaneousGesture(readerSwipeGesture)
    }

    /// Shows page status above the image and navigation below it.
    private var readerChromeOverlay: some View {
        VStack(spacing: 0) {
            readerStatusBar
                .background(.regularMaterial)

            Spacer()

            navigationControls
                .padding()
                .background(.regularMaterial)
        }
        .foregroundStyle(readerForegroundStyle)
    }

    /// Shows the current shared page number and zoom percentage.
    private var readerStatusBar: some View {
        HStack {
            Text(
                String(
                    format: AppCopy.readerPageKnownFormat,
                    String(currentIndex + 1),
                    String(records.count)
                )
            )
            .font(.subheadline.weight(.semibold))

            Spacer()

            Label(String(format: AppCopy.readerZoomFormat, visibleZoomTitle), systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(readerForegroundStyle.opacity(0.72))
        }
        .padding()
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let currentRecord {
            Button {
                store.toggleFavorite(currentRecord)
            } label: {
                Image(systemName: currentRecord.isFavorite ? "heart.fill" : "heart")
            }
            .accessibilityLabel(
                currentRecord.isFavorite ? AppCopy.sharedMediaUnfavorite : AppCopy.sharedMediaFavorite
            )
        }
    }

    /// Provides previous, jump, grid, and next actions matching the gallery reader.
    private var navigationControls: some View {
        HStack {
            Button {
                showPrevious()
            } label: {
                Label(AppCopy.readerPreviousPage, systemImage: "chevron.left")
            }
            .disabled(currentIndex == 0)

            Spacer()

            Button {
                presentPageJump()
            } label: {
                Label(AppCopy.readerJumpPage, systemImage: "number.square")
            }
            .disabled(records.isEmpty)

            Button {
                showsPageGridSheet = true
            } label: {
                Image(systemName: "square.grid.3x3")
                    .frame(width: 28, height: 20)
            }
            .disabled(records.isEmpty)
            .accessibilityLabel(AppCopy.readerPageGrid)

            Spacer()

            Button {
                showNext()
            } label: {
                Label(AppCopy.readerNextPage, systemImage: "chevron.right")
            }
            .disabled(currentIndex >= records.count - 1)
        }
        .buttonStyle(.bordered)
    }

    /// Shows a numeric jump form for the current shared image batch.
    private var pageJumpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.readerJumpPageField, text: $pageJumpText)
                        .keyboardType(.numberPad)

                    Text(String(format: AppCopy.readerJumpPageRangeFormat, String(records.count)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(AppCopy.readerJumpPageTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.readerJumpPageCancel) {
                        showsPageJumpSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.readerJumpPageConfirm) {
                        submitPageJump()
                    }
                    .disabled(!canSubmitPageJump)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Shows every shared image in the current batch as a selectable page.
    private var pageGridSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: ReaderPageGridLayout.columns, alignment: .leading, spacing: 10) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        Button {
                            currentIndex = index
                            showsPageGridSheet = false
                        } label: {
                            VStack(spacing: 6) {
                                GeometryReader { proxy in
                                    SharedMediaThumbnail(record: record)
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                }
                                .aspectRatio(ReaderPageGridLayout.thumbnailAspectRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                Text(String(format: AppCopy.galleryOpenPage, String(index + 1)))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(
                                index == currentIndex
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.secondary.opacity(0.08)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(AppCopy.readerPageGridTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.readerJumpPageCancel) {
                        showsPageGridSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Creates the tap zones used for previous, chrome, and next actions.
    private func readerTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleTap(location: value.location, width: size.width)
            }
    }

    /// Creates horizontal swipe navigation matching the gallery reader threshold.
    private var readerSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 44)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = abs(value.translation.height)
                guard abs(horizontalDistance) > 64, abs(horizontalDistance) > verticalDistance * 1.25 else { return }
                if horizontalDistance < 0 {
                    showNext()
                } else {
                    showPrevious()
                }
            }
    }

    /// Creates temporary pinch zoom on top of the persisted zoom level.
    private var readerPinchGesture: some Gesture {
        MagnificationGesture()
            .updating($transientPinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                persistedPinchScale = min(max(persistedPinchScale * value, 1), 4)
            }
    }

    /// Handles left, center, and right reader tap zones.
    private func handleTap(location: CGPoint, width: CGFloat) {
        if location.x < width * 0.3 {
            showPrevious()
        } else if location.x > width * 0.7 {
            showNext()
        } else {
            showsChrome.toggle()
        }
    }

    /// Advances to the next local image when available.
    private func showNext() {
        guard currentIndex < records.count - 1 else { return }
        currentIndex += 1
    }

    /// Returns to the previous local image when available.
    private func showPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    /// Opens the jump form with the current page number prefilled.
    private func presentPageJump() {
        pageJumpText = String(currentIndex + 1)
        showsPageJumpSheet = true
    }

    /// Applies a valid page number and closes the jump form.
    private func submitPageJump() {
        guard let pageJumpNumber, records.indices.contains(pageJumpNumber - 1) else { return }
        currentIndex = pageJumpNumber - 1
        showsPageJumpSheet = false
    }

    /// Calculates the image width from the shared fit and zoom settings.
    private func readerImageWidth(availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = fitMode == .fitPage ? 32 : 0
        let baseWidth = max(availableWidth - horizontalPadding, 44)
        return baseWidth * visibleZoomScale
    }

    /// Restores the saved zoom level and temporary pinch scale.
    private func resetReaderZoom() {
        zoomLevelRaw = ReaderZoomLevel.x1.rawValue
        persistedPinchScale = 1
    }

    /// Resets temporary UI when a new shared image becomes active.
    private func resetTransientReaderState() {
        showsChrome = false
        persistedPinchScale = 1
    }
}

/// Decodes one full-resolution local image away from the main actor.
private struct SharedLocalImageView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                AnimatedImageDataView(image: image, contentMode: .scaleAspectFit)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return ImageDataRenderer.uiImage(from: data, allowsAnimation: true)
            }.value
        }
    }
}
