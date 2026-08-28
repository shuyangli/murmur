import Foundation
import Combine

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    /// Wall-clock seconds the user held the trigger key.
    let audioDuration: TimeInterval
    /// Wall-clock seconds from key release to final transcript.
    let transcriptionDuration: TimeInterval
    let engineID: String
    /// Bundle identifier of the app that was frontmost, when known.
    let targetApplication: String?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        audioDuration: TimeInterval,
        transcriptionDuration: TimeInterval,
        engineID: String,
        targetApplication: String?
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.audioDuration = audioDuration
        self.transcriptionDuration = transcriptionDuration
        self.engineID = engineID
        self.targetApplication = targetApplication
    }
}

/// Newest-first list of past dictations, persisted as a single JSON file.
///
/// The file is disposable by design: any read or decode failure yields an
/// empty history rather than an error, because losing dictation history is
/// not worth interrupting the user over.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let limitProvider: () -> Int

    init(fileURL: URL? = nil, limitProvider: @escaping () -> Int) {
        self.fileURL = fileURL ?? AppPaths.supportDirectory.appendingPathComponent("history.json")
        self.limitProvider = limitProvider
        load()
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        trimAndSave()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func deleteAll() {
        entries.removeAll()
        save()
    }

    /// Re-applies the configured cap; call after the user lowers the limit.
    func applyLimit() {
        trimAndSave()
    }

    private func trimAndSave() {
        let limit = limitProvider()
        if entries.count > limit {
            entries.removeSubrange(limit...)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.murmur.decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        do {
            try AppPaths.ensureSupportDirectory()
            let data = try JSONEncoder.murmur.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension JSONEncoder {
    static var murmur: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var murmur: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Murmur", isDirectory: true)
    }

    static func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }
}
