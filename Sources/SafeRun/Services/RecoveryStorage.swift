import Foundation

enum RecoveryStorage {
    @concurrent
    static func byteCount() async -> Int64 {
        let root = TransactionStore.defaultRecoveryDirectory
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { return 0 }
        var bytes: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return bytes
    }
}
