import Combine
import Foundation
import MurmurCore

struct InstalledModel: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let description: ModelDescription
    let byteCount: Int64
    /// Top-level directory in the cache, used to match a download to an engine.
    let rootDirectoryName: String
    /// Path within the cache, used to tell one build of an engine from another.
    let relativeComponents: [String]

    var displayName: String { description.engineName }
    var displayVariant: String? { description.variant }

    func belongs(to descriptor: EngineDescriptor) -> Bool {
        guard let prefix = descriptor.cacheDirectoryPrefix else { return false }
        return rootDirectoryName.hasPrefix(prefix)
    }

    /// Whether this exact build is the one the current settings would load.
    ///
    /// Nemotron keeps a directory per vocabulary and chunk tier, so belonging
    /// to the selected engine is not enough — several of its builds can sit on
    /// disk while only one is loaded.
    func isInUse(descriptor: EngineDescriptor, language: String, chunkMilliseconds: Int) -> Bool {
        guard belongs(to: descriptor) else { return false }
        guard rootDirectoryName == "nemotron-multilingual" else { return true }
        return NemotronLayout.matches(
            pathComponents: relativeComponents,
            languageCode: language,
            chunkMilliseconds: chunkMilliseconds
        )
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}

/// Lists the speech models sitting in the shared model cache, and deletes them.
///
/// The cache belongs to FluidAudio rather than to Murmur, so nothing here
/// assumes it is the only writer: the list is rescanned from disk each time
/// instead of being tracked as the app downloads things.
@MainActor
final class ModelInventory: ObservableObject {
    @Published private(set) var models: [InstalledModel] = []
    @Published private(set) var isScanning = false

    /// Where FluidAudio caches everything it downloads.
    nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    /// Roots whose children are separate downloads rather than parts of one.
    /// Nemotron ships a directory per vocabulary and chunk tier, and each can
    /// be removed on its own.
    private nonisolated static let rootsWithVariants: Set<String> = ["nemotron-multilingual"]

    /// How deep the variant directories sit under such a root.
    private nonisolated static let variantDepth = 2

    var totalByteCount: Int64 {
        models.reduce(0) { $0 + $1.byteCount }
    }

    var formattedTotal: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalByteCount)
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        let root = Self.cacheDirectory
        Task {
            // Summing file sizes walks every file in the cache, which is well
            // over a gigabyte; keep it off the main thread.
            let found = await Task.detached(priority: .utility) {
                Self.scan(root: root)
            }.value
            self.models = found
            self.isScanning = false
        }
    }

    /// Removes the model's files. Returns false if the delete failed.
    @discardableResult
    func delete(_ model: InstalledModel) -> Bool {
        do {
            try FileManager.default.removeItem(at: model.url)
            pruneEmptyParents(of: model.url)
            models.removeAll { $0.id == model.id }
            Log.asr.info("Deleted model at \(model.url.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Log.asr.error("Could not delete model: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Deleting `latin/2240ms` leaves an empty `latin` behind, which would show
    /// up as a phantom zero-byte model on the next scan.
    private func pruneEmptyParents(of url: URL) {
        var parent = url.deletingLastPathComponent()
        let root = Self.cacheDirectory
        while parent.path.hasPrefix(root.path), parent.path != root.path {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: parent.path)
            guard contents?.isEmpty ?? false else { return }
            try? FileManager.default.removeItem(at: parent)
            parent = parent.deletingLastPathComponent()
        }
    }

    // MARK: - Scanning

    nonisolated static func scan(root: URL) -> [InstalledModel] {
        let manager = FileManager.default
        guard let roots = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [InstalledModel] = []
        for entry in roots where isDirectory(entry) {
            let name = entry.lastPathComponent
            let leaves = rootsWithVariants.contains(name)
                ? descendants(of: entry, depth: variantDepth)
                : [entry]

            for leaf in leaves {
                let components = relativeComponents(of: leaf, under: root)
                found.append(
                    InstalledModel(
                        url: leaf,
                        description: ModelNaming.describe(pathComponents: components),
                        byteCount: byteCount(of: leaf),
                        rootDirectoryName: name,
                        relativeComponents: components
                    )
                )
            }
        }

        return found.sorted {
            ($0.displayName, $0.displayVariant ?? "") < ($1.displayName, $1.displayVariant ?? "")
        }
    }

    private nonisolated static func descendants(of url: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [url] }
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [url] }

        let directories = children.filter(isDirectory)
        // A root that has not been populated the expected way is still worth
        // listing, so the user can reclaim the space.
        guard !directories.isEmpty else { return [url] }
        return directories.flatMap { descendants(of: $0, depth: depth - 1) }
    }

    private nonisolated static func relativeComponents(of url: URL, under root: URL) -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count else { return [url.lastPathComponent] }
        return Array(urlComponents.dropFirst(rootComponents.count))
    }

    private nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private nonisolated static func byteCount(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            // Allocated size is what the disk actually gives back on delete.
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
