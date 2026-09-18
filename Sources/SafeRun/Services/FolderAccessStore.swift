import Foundation

/// Persists user-selected folder permissions and keeps the currently used security scope active.
///
/// SafeRun stores only bookmark data locally. It never stores or transmits file contents.
final class FolderAccessStore {
    struct ResolvedBookmark {
        let url: URL
        let isStale: Bool
        let startedAccessing: Bool
    }

    typealias BookmarkFactory = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> ResolvedBookmark

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let bookmarkFactory: BookmarkFactory
    private let bookmarkResolver: BookmarkResolver
    private var activeAccess: ActiveAccess?

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "securityScopedFolderBookmarks"
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.bookmarkFactory = { url in
            try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        self.bookmarkResolver = { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                throw SafeRunError.accessDenied(url)
            }
            return ResolvedBookmark(
                url: url,
                isStale: isStale,
                startedAccessing: true
            )
        }
    }

    init(
        defaults: UserDefaults,
        defaultsKey: String,
        bookmarkFactory: @escaping BookmarkFactory,
        bookmarkResolver: @escaping BookmarkResolver
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.bookmarkFactory = bookmarkFactory
        self.bookmarkResolver = bookmarkResolver
    }

    deinit {
        releaseActiveAccess()
    }

    /// Saves a fresh bookmark for a folder selected through the system picker or drag and drop.
    func grantAccess(to url: URL) throws -> URL {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try bookmarkFactory(url)
        return try activate(bookmark: bookmark, requestedURL: url)
    }

    /// Restores a previously granted permission. Callers should ask the user to choose the folder
    /// again if no bookmark exists or the bookmark can no longer be resolved.
    func restoreAccess(to url: URL) throws -> URL {
        let key = bookmarkKey(for: url)
        guard let bookmark = loadBookmarks()[key] else {
            throw SafeRunError.accessDenied(url)
        }
        return try activate(bookmark: bookmark, requestedURL: url)
    }

    func releaseActiveAccess() {
        guard let activeAccess else { return }
        if activeAccess.startedAccessing {
            activeAccess.url.stopAccessingSecurityScopedResource()
        }
        self.activeAccess = nil
    }

    private func activate(bookmark: Data, requestedURL: URL) throws -> URL {
        let resolved = try bookmarkResolver(bookmark)
        let normalizedURL = PathValidator.normalized(resolved.url)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            if resolved.startedAccessing {
                resolved.url.stopAccessingSecurityScopedResource()
            }
            throw SafeRunError.folderNotFound
        }

        do {
            let refreshedBookmark = resolved.isStale ? try bookmarkFactory(resolved.url) : bookmark
            var bookmarks = loadBookmarks()
            bookmarks[bookmarkKey(for: requestedURL)] = refreshedBookmark
            bookmarks[bookmarkKey(for: normalizedURL)] = refreshedBookmark
            try saveBookmarks(bookmarks)
        } catch {
            if resolved.startedAccessing {
                resolved.url.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        releaseActiveAccess()
        activeAccess = ActiveAccess(url: resolved.url, startedAccessing: resolved.startedAccessing)
        return normalizedURL
    }

    private func loadBookmarks() -> [String: Data] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) throws {
        defaults.set(try JSONEncoder().encode(bookmarks), forKey: defaultsKey)
    }

    private func bookmarkKey(for url: URL) -> String {
        PathValidator.normalized(url).path
    }
}

private struct ActiveAccess {
    let url: URL
    let startedAccessing: Bool
}
