import Foundation

struct FolderContextScanner: Sendable {
    func scan(root: URL) async throws -> FolderContext {
        let root = PathValidator.normalized(root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw SafeRunError.folderNotFound
        }
        guard isDirectory.boolValue else {
            throw SafeRunError.selectedItemIsNotDirectory
        }

        return try await Task.detached(priority: .userInitiated) {
            try self.scanSynchronously(root: root)
        }.value
    }

    private func scanSynchronously(root: URL) throws -> FolderContext {
            let fileManager = FileManager.default
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey
            ]
            var entries: [FolderEntry] = []

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) else {
                throw SafeRunError.accessDenied(root)
            }

            for case let url as URL in enumerator {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: keys)
                let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
                entries.append(
                    FolderEntry(
                        url: url,
                        relativePath: relativePath,
                        name: url.lastPathComponent,
                        fileExtension: url.pathExtension.lowercased(),
                        byteSize: Int64(values.fileSize ?? 0),
                        createdAt: values.creationDate,
                        modifiedAt: values.contentModificationDate,
                        isDirectory: values.isDirectory ?? false,
                        isSymbolicLink: values.isSymbolicLink ?? false
                    )
                )
            }

            return FolderContext(rootFolder: root, entries: entries, generatedAt: .now)
    }
}
