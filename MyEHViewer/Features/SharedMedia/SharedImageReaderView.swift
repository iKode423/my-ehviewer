import SwiftUI

/// Reads persistent shared images with the same tap, swipe, and favorite flow as gallery pages.
struct SharedImageReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SharedMediaStore
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    let records: [SharedMediaRecord]
    let initialRecordID: UUID
    @State private var currentIndex: Int
    @State private var showsChrome = true
    @State private var showsPageGrid = false
    @State private var persistedScale: CGFloat = 1
    @GestureState private var transientScale: CGFloat = 1

    /// Creates a local reader positioned at the selected shared image.
    init(records: [SharedMediaRecord], initialRecordID: UUID) {
        self.records = records
        self.initialRecordID = initialRecordID
        _currentIndex = State(initialValue: records.firstIndex(where: { $0.id == initialRecordID }) ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                readerBackground.ignoresSafeArea()

                if let record = currentRecord {
                    SharedLocalImageView(url: store.fileURL(for: record))
                        .scaleEffect(persistedScale * transientScale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(swipeGesture)
                        .simultaneousGesture(pinchGesture)
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                handleTap(location: value.location, width: proxy.size.width)
                            }
                        )
                } else {
                    ContentUnavailableView(AppCopy.sharedMediaEmptyTitle, systemImage: "photo")
                }

                if showsChrome {
                    chromeOverlay
                        .transition(.opacity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!showsChrome)
        .sheet(isPresented: $showsPageGrid) { pageGrid }
        .onChange(of: currentIndex) { _, _ in resetZoom() }
    }

    private var currentRecord: SharedMediaRecord? {
        guard records.indices.contains(currentIndex) else { return nil }
        return store.records.first(where: { $0.id == records[currentIndex].id }) ?? records[currentIndex]
    }

    private var readerBackground: Color {
        switch ReaderBackgroundMode(rawValue: backgroundModeRaw) ?? .system {
        case .system: Color(uiColor: .systemBackground)
        case .dark: .black
        case .paper: Color(red: 0.96, green: 0.93, blue: 0.86)
        }
    }

    private var chromeOverlay: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppCopy.readerClose)

                Text(currentRecord?.displayName ?? AppCopy.sharedMediaTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()

                if let currentRecord {
                    Button { store.toggleFavorite(currentRecord) } label: {
                        Image(systemName: currentRecord.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(currentRecord.isFavorite ? .pink : .primary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AppCopy.sharedMediaFavorite)
                }
            }
            .padding(.horizontal, 6)
            .background(.regularMaterial)

            Spacer()

            HStack(spacing: 18) {
                Button { showPrevious() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0)

                Text("\(currentIndex + 1) / \(records.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))

                Button { showsPageGrid = true } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel(AppCopy.readerPageGrid)

                Button { showNext() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex >= records.count - 1)
            }
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(height: 50)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 18)
        }
    }

    private var pageGrid: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        Button {
                            currentIndex = index
                            showsPageGrid = false
                        } label: {
                            VStack(spacing: 5) {
                                SharedMediaThumbnail(record: record)
                                    .aspectRatio(0.72, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(String(index + 1))
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(AppCopy.readerPageGrid)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -50 {
                    showNext()
                } else if value.translation.width > 50 {
                    showPrevious()
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($transientScale) { value, state, _ in state = value }
            .onEnded { value in persistedScale = min(5, max(1, persistedScale * value)) }
    }

    /// Handles left, center, and right reader tap zones.
    private func handleTap(location: CGPoint, width: CGFloat) {
        if location.x < width * 0.3 {
            showPrevious()
        } else if location.x > width * 0.7 {
            showNext()
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { showsChrome.toggle() }
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

    /// Restores the default scale after changing pages.
    private func resetZoom() {
        persistedScale = 1
    }
}

/// Decodes one full-resolution local image away from the main actor.
private struct SharedLocalImageView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
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
