import UIKit
import UniformTypeIdentifiers

/// Receives shared images and videos and copies them into the App Group inbox.
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
        do {
            let providers = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .compactMap(\.attachments)
                .flatMap { $0 } ?? []
            let supportedProviders = providers.compactMap { provider -> (NSItemProvider, SharedMediaKind, UTType)? in
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    return (provider, .video, .movie)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    return (provider, .image, .image)
                }
                return nil
            }
            guard !supportedProviders.isEmpty else {
                throw ShareImportError.noSupportedItems
            }

            let batchID = UUID()
            let batchDirectory = try makeBatchDirectory(batchID: batchID)
            var items: [SharedMediaIncomingItem] = []
            for (index, value) in supportedProviders.enumerated() {
                let item = try await copyItem(
                    provider: value.0,
                    kind: value.1,
                    type: value.2,
                    destinationDirectory: batchDirectory
                )
                items.append(item)
                progressView.progress = Float(index + 1) / Float(supportedProviders.count)
            }

            let manifest = SharedMediaIncomingManifest(batchID: batchID, importedAt: Date(), items: items)
            let data = try JSONEncoder().encode(manifest)
            try data.write(
                to: batchDirectory.appending(path: SharedMediaConstants.manifestFilename),
                options: [.atomic]
            )
            statusLabel.text = "已保存 \(items.count) 个项目"
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.text = "保存失败\n\(error.localizedDescription)"
            extensionContext?.cancelRequest(withError: error)
        }
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
}

/// Describes failures that can occur before shared media reaches the host app.
private enum ShareImportError: LocalizedError {
    case noSupportedItems
    case sharedContainerUnavailable
    case missingTemporaryFile

    var errorDescription: String? {
        switch self {
        case .noSupportedItems: "没有可保存的图片或视频。"
        case .sharedContainerUnavailable: "无法访问共享媒体目录。"
        case .missingTemporaryFile: "分享来源没有提供可读取的文件。"
        }
    }
}
