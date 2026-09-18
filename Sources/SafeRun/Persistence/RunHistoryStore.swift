import Foundation

actor RunHistoryStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SafeRun", isDirectory: true)
            .appendingPathComponent("history.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [RunHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? decoder.decode([RunHistoryItem].self, from: data) else {
            return []
        }
        return history.sorted { $0.timestamp > $1.timestamp }
    }

    func append(_ item: RunHistoryItem) throws {
        var history = load()
        history.insert(item, at: 0)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}
