import Foundation
import CryptoKit
import Darwin

struct StalePlanError: LocalizedError, Sendable {
    let changedPaths: [String]
    var errorDescription: String? {
        "Filesystem changed at \(changedPaths.joined(separator: ", ")). Re-simulate before execution."
    }
}

/// A simulation's immutable filesystem inputs. Directory timestamps deliberately do not
/// participate: adding an unrelated child must not invalidate a directory's identity.
struct FileSnapshot: Codable, Hashable, Sendable {
    struct Action: Codable, Hashable, Sendable {
        let id: UUID
        let type: SafeRunActionType
        let source: URL?
        let destination: URL?

        init(_ action: SafeRunAction) {
            id = action.id
            type = action.type
            source = action.sourceURL?.standardizedFileURL
            destination = action.destinationURL?.standardizedFileURL
        }
    }

    let planID: UUID
    let root: URL
    let actions: [Action]
    let files: [String: FileIdentity]

    static func capture(plan: SafeRunPlan) throws -> FileSnapshot {
        try Task.checkCancellation()
        let root = plan.selectedRootFolder.standardizedFileURL
        guard try FileIdentity.read(root).kind == .directory else {
            throw SafeRunError.accessDenied(root)
        }
        var files: [String: FileIdentity] = [:]
        for action in plan.actions {
            for url in [action.sourceURL, action.destinationURL].compactMap({ $0 }) {
                try validatePath(url, root: root)
                var current = url.standardizedFileURL
                while true {
                    if files[current.path] == nil {
                        files[current.path] = try FileIdentity.read(current, checkingCancellation: true)
                    }
                    if current == root { break }
                    current.deleteLastPathComponent()
                }
            }
        }
        files[root.path] = try FileIdentity.read(root)
        return FileSnapshot(planID: plan.id, root: root, actions: plan.actions.map(Action.init), files: files)
    }

    func verify(plan: SafeRunPlan) throws {
        guard plan.id == planID, plan.selectedRootFolder.standardizedFileURL == root,
              plan.actions.map(Action.init) == actions else {
            throw SafeRunError.planNotExecutable("The plan changed after simulation. Re-simulate before execution.")
        }
        for (path, expected) in files {
            let url = URL(fileURLWithPath: path)
            if url != root { try Self.validatePath(url, root: root) }
            try expected.requireMatch(at: url)
        }
    }

    static func validatePath(_ url: URL, root: URL) throws {
        let candidate = url.standardizedFileURL
        let root = root.standardizedFileURL
        guard url.isFileURL, candidate != root,
              candidate.path.hasPrefix(root.path == "/" ? "/" : root.path + "/"),
              PathValidator.isWithinRoot(candidate, root: root),
              PathValidator.isValidFileName(candidate.lastPathComponent) else {
            throw SafeRunError.invalidPath(url)
        }
        var current = candidate
        while true {
            var info = stat()
            let result = lstat(current.path, &info)
            if result == 0, info.st_mode & S_IFMT == S_IFLNK { throw SafeRunError.invalidPath(current) }
            if result != 0, errno != ENOENT { throw TransactionStore.posixError() }
            if current == root { break }
            current.deleteLastPathComponent()
        }
    }
}

struct FileIdentity: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case absent, file, directory, symbolicLink, other }
    let kind: Kind
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let digest: String?

    static let absent = FileIdentity(kind: .absent, device: 0, inode: 0, size: 0,
                                     modifiedSeconds: 0, modifiedNanoseconds: 0, digest: nil)

    static func read(_ url: URL) throws -> FileIdentity {
        try read(url, checkingCancellation: false)
    }

    static func read(_ url: URL, checkingCancellation: Bool) throws -> FileIdentity {
        if checkingCancellation { try Task.checkCancellation() }
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return .absent }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let kind: Kind
        switch info.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }
        var digest: String?
        if kind == .file {
            let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var opened = stat()
            guard fstat(fd, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else {
                throw SafeRunError.executionFailed("File changed while inspecting \(url.path).")
            }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                if checkingCancellation { try Task.checkCancellation() }
                hash.update(data: chunk)
            }
            digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            var after = stat()
            guard fstat(fd, &after) == 0, after.st_size == info.st_size,
                  after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == info.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec else {
                throw SafeRunError.executionFailed("File changed while inspecting \(url.path).")
            }
        }
        return FileIdentity(kind: kind, device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                            size: kind == .file ? info.st_size : 0,
                            modifiedSeconds: kind == .file ? Int64(info.st_mtimespec.tv_sec) : 0,
                            modifiedNanoseconds: kind == .file ? Int64(info.st_mtimespec.tv_nsec) : 0,
                            digest: digest)
    }

    func requireMatch(at url: URL) throws {
        guard try Self.read(url) == self else {
            throw StalePlanError(changedPaths: [url.path])
        }
    }
}

struct ExecutionTransaction: Codable, Hashable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case executing, completed, recovering, recoveryRequired, rolledBack, expired }
    struct Entry: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Sendable { case prepared, staged, backingUp, backedUp, publishing, applied, undoing, undone }
        let action: SafeRunAction
        let sourceBefore: FileIdentity?
        let destinationBefore: FileIdentity?
        let stagingURL: URL
        let backupURL: URL
        let undoURL: URL
        var installed: FileIdentity?
        var phase: Phase = .prepared
        var failure: String?
    }
    let id: UUID
    let journal: RollbackJournal
    let snapshot: FileSnapshot
    var entries: [Entry] = []
    var state: State = .executing
    var failure: String?
}
