import Foundation

/// Only this explicit allowlist is encoded; FolderContext/FolderEntry contain private absolute URLs.
struct PlannerMetadata: Encodable, Sendable {
    static let maximumEntries = 500
    static let maximumRequestBytes = 131_072
    static let maximumInstructionBytes = 8_000

    let rootDirectory = "."
    let instruction: String
    let entries: [Entry]
    let omittedEntryCount: Int

    struct Entry: Encodable, Sendable {
        let relativePath: String
        let filename: String
        let byteSize: Int64
        let createdAt: Date?
        let modifiedAt: Date?
        let type: String
    }

    init(instruction: String, context: FolderContext) throws {
        guard instruction.utf8.count <= Self.maximumInstructionBytes else {
            throw AIPlannerError.inputTooLarge
        }
        // Explicitly pasted references to the selected root stay local too.
        self.instruction = instruction
            .replacingOccurrences(of: context.rootFolder.absoluteString, with: ".")
            .replacingOccurrences(of: context.rootFolder.path, with: ".")
        var selected: [Entry] = []
        for entry in context.entries.prefix(Self.maximumEntries) {
            guard AIPlanDTO.isRelativePath(entry.relativePath), entry.byteSize >= 0,
                  entry.url.standardizedFileURL == context.rootFolder
                    .appendingPathComponent(entry.relativePath, isDirectory: entry.isDirectory).standardizedFileURL else {
                throw AIPlannerError.invalidMetadata
            }
            // Symbolic links can expose names or targets outside the selected folder.
            guard !entry.isSymbolicLink, entry.isAlias != true, entry.isPackage != true else { continue }
            selected.append(Entry(
                relativePath: entry.relativePath,
                filename: (entry.relativePath as NSString).lastPathComponent,
                byteSize: entry.byteSize, createdAt: entry.createdAt, modifiedAt: entry.modifiedAt,
                type: entry.isDirectory ? "directory" : "file"
            ))
        }
        self.entries = selected
        self.omittedEntryCount = context.entries.count - selected.count
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(self) }
        catch { throw AIPlannerError.invalidMetadata }
        guard data.count <= Self.maximumRequestBytes,
              let text = String(data: data, encoding: .utf8) else {
            throw AIPlannerError.inputTooLarge
        }
        return text
    }
}
