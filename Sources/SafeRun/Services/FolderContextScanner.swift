import Foundation

struct FolderContextScanner: Sendable {
    @concurrent
    func scan(
        root: URL,
        maximumEntries: Int = 50_000,
        onProgress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async throws -> FolderContext {
        let root = PathValidator.normalized(root)
        let manager = FileManager.default
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey, .isPackageKey])
        guard rootValues.isDirectory == true, rootValues.isPackage != true else {
            throw SafeRunError.selectedItemIsNotDirectory
        }
        guard rootValues.isReadable == true else { throw SafeRunError.accessDenied(root) }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey,
            .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]
        // Stop on unreadable subtrees instead of presenting an incomplete snapshot as complete.
        let issues = ScanIssues()
        guard let enumerator = manager.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants],
            errorHandler: { _, _ in issues.failed = true; return false }
        ) else { throw SafeRunError.accessDenied(root) }

        var entries: [FolderEntry] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard entries.count < maximumEntries else {
                throw SafeRunError.planNotExecutable("This folder exceeds the \(maximumEntries) item scan limit. Choose a smaller subfolder.")
            }
            let values = try url.resourceValues(forKeys: keys)
            let isLink = values.isSymbolicLink == true
            let isAlias = values.isAliasFile == true
            let isPackage = values.isPackage == true
            if isLink || isAlias || isPackage { enumerator.skipDescendants() }
            let relativePath = String(url.path.dropFirst(root.path.count + 1))
            entries.append(FolderEntry(
                url: url, relativePath: relativePath, name: url.lastPathComponent,
                fileExtension: url.pathExtension.lowercased(), byteSize: Int64(values.fileSize ?? 0),
                createdAt: values.creationDate, modifiedAt: values.contentModificationDate,
                isDirectory: values.isDirectory ?? false, isSymbolicLink: isLink,
                isAlias: isAlias, isPackage: isPackage
            ))
            if entries.count.isMultiple(of: 100) { await onProgress(entries.count) }
        }
        try Task.checkCancellation()
        guard !issues.failed else { throw SafeRunError.accessDenied(root) }
        await onProgress(entries.count)
        let excluded = entries.filter { $0.isSymbolicLink || $0.isAlias == true || $0.isPackage == true }.count
        return FolderContext(
            rootFolder: root, entries: entries, generatedAt: .now,
            scanWarnings: excluded == 0 ? [] : ["\(excluded) symbolic links, aliases, or packages were listed but their contents were not scanned. Operations on them are blocked."]
        )
    }
}

private final class ScanIssues {
    var failed = false
}
