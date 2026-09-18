import Foundation

actor RollbackStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SafeRun", isDirectory: true)
            .appendingPathComponent("rollbacks.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [RollbackJournal] {
        guard let data = try? Data(contentsOf: fileURL),
              let journals = try? decoder.decode([RollbackJournal].self, from: data) else {
            return []
        }
        return journals.sorted { $0.createdAt > $1.createdAt }
    }

    func append(_ journal: RollbackJournal) throws {
        var journals = load()
        journals.removeAll { $0.id == journal.id }
        journals.insert(journal, at: 0)
        try persist(journals)
    }

    func remove(_ journalID: UUID) throws {
        let journals = load().filter { $0.id != journalID }
        try persist(journals)
    }

    private func persist(_ journals: [RollbackJournal]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(journals).write(to: fileURL, options: .atomic)
    }
}
