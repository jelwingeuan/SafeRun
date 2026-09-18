import Foundation
import Darwin

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
        var journals = try loadVerified()
        journals.removeAll { $0.id == journal.id }
        journals.insert(journal, at: 0)
        try persist(journals)
    }

    func remove(_ journalID: UUID) throws {
        let journals = try loadVerified().filter { $0.id != journalID }
        try persist(journals)
    }

    private func persist(_ journals: [RollbackJournal]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TransactionStore.durableWrite(encoder.encode(journals), to: fileURL)
    }

    func loadVerified() throws -> [RollbackJournal] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([RollbackJournal].self, from: Data(contentsOf: fileURL))
            .sorted { $0.createdAt > $1.createdAt }
    }
}

/// Each transaction is independently durable; corrupt JSON is surfaced, never replaced
/// with an empty history. File and containing directory are synced before returning.
struct TransactionStore: Sendable {
    static var defaultRecoveryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SafeRun/Recovery", isDirectory: true)
    }
    let directory: URL

    func save(_ transaction: ExecutionTransaction) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Self.durableWrite(encoder.encode(transaction), to: url(transaction.id))
    }

    func load(_ id: UUID) throws -> ExecutionTransaction {
        try JSONDecoder().decode(ExecutionTransaction.self, from: Data(contentsOf: url(id)))
    }

    func all() throws -> [ExecutionTransaction] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(ExecutionTransaction.self, from: Data(contentsOf: $0)) }
            .sorted { $0.journal.createdAt > $1.journal.createdAt }
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    static func durableWrite(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".transaction-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(temporary.path, url.path) == 0 else { throw posixError() }
        try syncDirectory(url.deletingLastPathComponent())
    }

    static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw posixError() }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw posixError() }
    }

    static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
