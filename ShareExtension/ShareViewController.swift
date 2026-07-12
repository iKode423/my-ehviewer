import UIKit
import UniformTypeIdentifiers

/// Receives shared media or one folder and copies it into the App Group inbox.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var hasStarted = false

    /// Builds the compact progress interface used inside the system share sheet.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "正在保存分享媒体"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [statusLabel, progressView])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// Starts importing once the extension is visible and its input is ready.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        Task { await importSharedItems() }
    }

    /// Copies every supported attachment and writes one batch manifest.
    private func importSharedItems() async {
        var batchDirectory: URL?
        do {
            let providers = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .compactMap(\.attachments)
                .flatMap { $0 } ?? []

            let batchID = UUID()
            let createdBatchDirectory = try makeBatchDirectory(batchID: batchID)
            batchDirectory = createdBatchDirectory
            let items: [SharedMediaIncomingItem]
            let gallery: SharedMediaIncomingGallery?
            let folderProviders = providers.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.folder.identifier)
            }
            if !folderProviders.isEmpty {
                guard folderProviders.count == 1, providers.count == 1 else {
                    throw ShareImportError.multipleFolders
                }
                let folderResult = try await copyFolder(
                    provider: folderProviders[0],
                    destinationDirectory: createdBatchDirectory
                )
                items = folderResult.items
                gallery = folderResult.gallery
            } else {
                let supportedProviders = providers.compactMap(Self.supportedMediaProvider)
                guard !supportedProviders.isEmpty else { throw ShareImportError.noSupportedItems }
                var copiedItems: [SharedMediaIncomingItem] = []
                for (index, value) in supportedProviders.enumerated() {
                    let item = try await copyItem(
                        provider: value.provider,
                        kind: value.kind,
                        type: value.type,
                        destinationDirectory: createdBatchDirectory
                    )
                    copiedItems.append(item)
                    progressView.progress = Float(index + 1) / Float(supportedProviders.count)
                }
                items = copiedItems
                gallery = nil
            }

            let manifest = SharedMediaIncomingManifest(
                batchID: batchID,
                importedAt: Date(),
                items: items,
                gallery: gallery
            )
            let data = try JSONEncoder().encode(manifest)
            try data.write(
                to: createdBatchDirectory.appending(path: SharedMediaConstants.manifestFilename),
                options: [.atomic]
            )
            statusLabel.text = "已保存 \(items.count) 个项目"
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            if let batchDirectory {
                try? FileManager.default.removeItem(at: batchDirectory)
            }
            statusLabel.text = "保存失败\n\(error.localizedDescription)"
            extensionContext?.cancelRequest(withError: error)
        }
    }

    /// Classifies one item provider as an image or video attachment.
    private static func supportedMediaProvider(
        _ provider: NSItemProvider
    ) -> (provider: NSItemProvider, kind: SharedMediaKind, type: UTType)? {
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return (provider, .video, .movie)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return (provider, .image, .image)
        }
        return nil
    }

    /// Creates one isolated incoming directory inside the shared container.
    private func makeBatchDirectory(batchID: UUID) throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedMediaConstants.appGroupIdentifier
        ) else {
            throw ShareImportError.sharedContainerUnavailable
        }
        let incomingURL = containerURL.appending(path: SharedMediaConstants.incomingDirectoryName, directoryHint: .isDirectory)
        let batchURL = incomingURL.appending(path: batchID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: batchURL, withIntermediateDirectories: true)
        return batchURL
    }

    /// Copies a temporary NSItemProvider file before the provider invalidates its URL.
    private func copyItem(
        provider: NSItemProvider,
        kind: SharedMediaKind,
        type: UTType,
        destinationDirectory: URL
    ) async throws -> SharedMediaIncomingItem {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { sourceURL, error in
                do {
                    if let error { throw error }
                    guard let sourceURL else { throw ShareImportError.missingTemporaryFile }
                    let originalFilename = suggestedName.flatMap { name in
                        sourceURL.pathExtension.isEmpty ? name : "\(name).\(sourceURL.pathExtension)"
                    } ?? sourceURL.lastPathComponent
                    let itemID = UUID()
                    let pathExtension = sourceURL.pathExtension
                    let storedFilename = pathExtension.isEmpty
                        ? itemID.uuidString
                        : "\(itemID.uuidString).\(pathExtension)"
                    let destinationURL = destinationDirectory.appending(path: storedFilename)
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume(returning: SharedMediaIncomingItem(
                        id: itemID,
                        kind: kind,
                        storedFilename: storedFilename,
                        originalFilename: originalFilename,
                        contentType: type.identifier
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Copies all supported descendants from one shared folder before access expires.
    private func copyFolder(
        provider: NSItemProvider,
        destinationDirectory: URL
    ) async throws -> (items: [SharedMediaIncomingItem], gallery: SharedMediaIncomingGallery) {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.folder.identifier) {
                sourceURL,
                _,
                error in
                do {
                    if let error { throw error }
                    guard let sourceURL else { throw ShareImportError.missingTemporaryFile }
                    let hasAccess = sourceURL.startAccessingSecurityScopedResource()
                    defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
                    let candidates = try Self.folderCandidates(in: sourceURL)
                    guard !candidates.isEmpty else { throw ShareImportError.noSupportedItems }

                    var items: [SharedMediaIncomingItem] = []
                    for (index, candidate) in candidates.enumerated() {
                        let itemID = UUID()
                        let pathExtension = candidate.url.pathExtension
                        let storedFilename = pathExtension.isEmpty
                            ? itemID.uuidString
                            : "\(itemID.uuidString).\(pathExtension)"
                        try FileManager.default.copyItem(
                            at: candidate.url,
                            to: destinationDirectory.appending(path: storedFilename)
                        )
                        items.append(SharedMediaIncomingItem(
                            id: itemID,
                            kind: candidate.kind,
                            storedFilename: storedFilename,
                            originalFilename: candidate.relativePath,
                            contentType: candidate.contentType.identifier
                        ))
                        let progress = Float(index + 1) / Float(candidates.count)
                        DispatchQueue.main.async { self.progressView.progress = progress }
                    }
                    let title = sourceURL.lastPathComponent.isEmpty
                        ? (suggestedName ?? "本地图库")
                        : sourceURL.lastPathComponent
                    continuation.resume(returning: (
                        items,
                        SharedMediaIncomingGallery(title: title, memberIDs: items.map(\.id))
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Recursively enumerates safe supported files in natural relative-path order.
    nonisolated private static func folderCandidates(in rootURL: URL) throws -> [SharedFolderCandidate] {
        let fileManager = FileManager.default
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true else { throw ShareImportError.missingTemporaryFile }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .contentTypeKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ShareImportError.missingTemporaryFile
        }

        var candidates: [SharedFolderCandidate] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .contentTypeKey
            ])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let resolvedURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            guard contains(resolvedURL, in: root) else { continue }
            guard let contentType = values.contentType ?? UTType(filenameExtension: fileURL.pathExtension) else {
                continue
            }
            let kind: SharedMediaKind
            if contentType.conforms(to: .image) {
                kind = .image
            } else if contentType.conforms(to: .movie) {
                kind = .video
            } else {
                continue
            }
            let relativePath = String(
                resolvedURL.path(percentEncoded: false).dropFirst(
                    root.path(percentEncoded: false).count + 1
                )
            )
            guard !relativePath.isEmpty else { continue }
            candidates.append(SharedFolderCandidate(
                url: resolvedURL,
                relativePath: relativePath,
                kind: kind,
                contentType: contentType
            ))
        }
        return candidates.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    /// Confirms one resolved file stays below the selected root folder.
    nonisolated private static func contains(_ childURL: URL, in rootURL: URL) -> Bool {
        childURL.path(percentEncoded: false).hasPrefix(rootURL.path(percentEncoded: false) + "/")
    }
}

/// Holds one supported file discovered inside a shared folder.
private struct SharedFolderCandidate {
    let url: URL
    let relativePath: String
    let kind: SharedMediaKind
    let contentType: UTType
}

/// Describes failures that can occur before shared media reaches the host app.
private enum ShareImportError: LocalizedError {
    case noSupportedItems
    case multipleFolders
    case sharedContainerUnavailable
    case missingTemporaryFile

    var errorDescription: String? {
        switch self {
        case .noSupportedItems: "没有可保存的图片或视频。"
        case .multipleFolders: "每次只能分享一个文件夹。"
        case .sharedContainerUnavailable: "无法访问共享媒体目录。"
        case .missingTemporaryFile: "分享来源没有提供可读取的文件。"
        }
    }
}
