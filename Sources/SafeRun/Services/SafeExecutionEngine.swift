import Foundation
import Darwin

struct SafeExecutionEngine: Sendable {
    let recoveryDirectory: URL
    let transactionStore: TransactionStore

    init(recoveryDirectory: URL? = nil, transactionDirectory: URL? = nil) {
        let recovery = (recoveryDirectory ?? TransactionStore.defaultRecoveryDirectory).standardizedFileURL
        self.recoveryDirectory = recovery
        transactionStore = TransactionStore(directory: transactionDirectory ?? recovery.appendingPathComponent("Transactions"))
    }

    func validateApproval(plan: SafeRunPlan, simulation: SimulationResult, userApproved: Bool) throws {
        guard userApproved else { throw SafeRunError.executionUnavailable }
        guard plan.status == .simulationComplete || plan.status == .approved,
              simulation.success, simulation.canExecute, simulation.actionsFailed == 0,
              simulation.conflicts.isEmpty, simulation.actionsPassed == plan.actions.count else {
            throw SafeRunError.planNotExecutable("SafeRun requires a successful simulation of every approved action.")
        }
    }

    @concurrent
    func execute(
        plan: SafeRunPlan,
        simulation: SimulationResult,
        userApproved: Bool,
        onProgress: @escaping @Sendable (ExecutionProgress) async -> Void = { _ in }
    ) async throws -> ExecutionReport {
        try validateApproval(plan: plan, simulation: simulation, userApproved: userApproved)
        guard let snapshot = simulation.snapshot else {
            throw SafeRunError.planNotExecutable("This simulation has no file snapshot. Re-simulate before execution.")
        }
        let lock = try acquireLock()
        defer { flock(lock, LOCK_UN); close(lock) }
        try snapshot.verify(plan: plan)
        guard !plan.actions.isEmpty, Set(plan.actions.map(\.id)).count == plan.actions.count else {
            throw SafeRunError.planNotExecutable("The plan is empty or has duplicate action identifiers.")
        }
        let journal = RollbackManager(recoveryDirectory: recoveryDirectory).makeJournal(for: plan)
        var transaction = ExecutionTransaction(id: journal.id, journal: journal, snapshot: snapshot)
        // The initial record exists even if preparation is interrupted.
        try transactionStore.save(transaction)
        let storage = recoveryDirectory.appendingPathComponent(journal.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        var expected = snapshot.files
        do {
            for (index, action) in plan.actions.enumerated() {
                try Task.checkCancellation()
                try verify(action, root: snapshot.root, expected: expected)
                let prefix = storage.appendingPathComponent(action.id.uuidString)
                let entry = ExecutionTransaction.Entry(
                    action: action,
                    sourceBefore: try action.sourceURL.map(FileIdentity.read),
                    destinationBefore: try action.destinationURL.map(FileIdentity.read),
                    stagingURL: prefix.appendingPathExtension("stage"),
                    backupURL: prefix.appendingPathExtension("backup"),
                    undoURL: prefix.appendingPathExtension("undo")
                )
                transaction.entries.append(entry)
                try transactionStore.save(transaction) // WAL before even staging an action.
                try coordinate(action) {
                    try verify(action, root: snapshot.root, expected: expected)
                    try apply(index, transaction: &transaction)
                }
                for url in [action.sourceURL, action.destinationURL].compactMap({ $0 }) {
                    expected[url.standardizedFileURL.path] = try FileIdentity.read(url)
                }
                await onProgress(ExecutionProgress(completedActions: index + 1, totalActions: plan.actions.count,
                                                   currentAction: action.description))
            }
            transaction.state = .completed
            try transactionStore.save(transaction)
        } catch {
            let original = error
            transaction.failure = original.localizedDescription
            if !transaction.entries.isEmpty { transaction.entries[transaction.entries.count - 1].failure = original.localizedDescription }
            do {
                try undo(&transaction)
            } catch {
                throw SafeRunError.executionFailed("Execution failed: \(original.localizedDescription) Recovery incomplete: \(error.localizedDescription) Transaction \(transaction.id) and recovery files were preserved.")
            }
            if original is CancellationError { throw CancellationError() }
            throw SafeRunError.executionFailed("Execution stopped; completed changes were rolled back. \(original.localizedDescription)")
        }
        return ExecutionReport(journal: journal, completedActionIDs: plan.actions.map(\.id))
    }

    @concurrent
    func rollback(_ journal: RollbackJournal) async throws {
        let lock = try acquireLock()
        defer { flock(lock, LOCK_UN); close(lock) }
        var transaction = try transactionStore.load(journal.id)
        guard transaction.journal == journal else { throw SafeRunError.executionFailed("Rollback journal does not match its durable transaction.") }
        try undo(&transaction)
    }

    func discoverInterruptedTransactions() throws -> [ExecutionTransaction] {
        try transactionStore.all().filter { [.executing, .recovering, .recoveryRequired].contains($0.state) }
    }

    /// Rebuild the UI's rollback/history indexes when the process exited after the
    /// transaction commit but before those derived indexes were saved.
    func completedJournals() throws -> [RollbackJournal] {
        try transactionStore.all().filter { $0.state == .completed }.map(\.journal)
    }

    func allTransactions() throws -> [ExecutionTransaction] { try transactionStore.all() }

    func recoveryStorageBytes() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return 0 }
        var total: Int64 = 0
        // Enumerate only known transaction storage; unrelated files are never cleanup targets.
        for transaction in try transactionStore.all() {
            for entry in transaction.entries {
                try validateStorage(entry, transactionID: transaction.id)
                for url in [entry.stagingURL, entry.backupURL, entry.undoURL] {
                    let identity = try FileIdentity.read(url)
                    if identity.kind == .file { total += identity.size }
                }
            }
        }
        return total
    }

    /// Explicit retention operation. Tombstones remain durable so a crash during
    /// cleanup cannot make incomplete rollback data appear usable on next launch.
    func cleanupCompletedTransactions(olderThan cutoff: Date) throws -> [UUID] {
        let lock = try acquireLock()
        defer { flock(lock, LOCK_UN); close(lock) }
        var expired: [UUID] = []
        for var transaction in try transactionStore.all()
        where transaction.journal.createdAt < cutoff && [.completed, .rolledBack, .expired].contains(transaction.state) {
            var targets: [(URL, FileIdentity)] = []
            for entry in transaction.entries {
                try validateStorage(entry, transactionID: transaction.id)
                let backupIdentity = entry.action.type == .deleteFile ? entry.sourceBefore : entry.destinationBefore
                for (url, identity) in [(entry.stagingURL, entry.installed), (entry.backupURL, backupIdentity), (entry.undoURL, entry.installed)] {
                    let current = try FileIdentity.read(url)
                    if current.kind == .absent { continue }
                    guard let identity, current == identity, [.file, .directory].contains(current.kind) else {
                        throw SafeRunError.executionFailed("Recovery content changed at \(url.path); retention cleanup left it intact.")
                    }
                    if current.kind == .directory,
                       !(try FileManager.default.contentsOfDirectory(atPath: url.path)).isEmpty {
                        throw SafeRunError.executionFailed("Recovery directory is not empty: \(url.path).")
                    }
                    targets.append((url, identity))
                }
            }
            transaction.state = .expired
            try transactionStore.save(transaction)
            for (url, identity) in targets {
                try identity.requireMatch(at: url)
                let result = identity.kind == .directory ? rmdir(url.path) : unlink(url.path)
                guard result == 0 else { throw TransactionStore.posixError() }
                try TransactionStore.syncDirectory(url.deletingLastPathComponent())
            }
            expired.append(transaction.id)
        }
        return expired
    }

    @concurrent
    func recover(_ transactionID: UUID) async throws {
        let lock = try acquireLock()
        defer { flock(lock, LOCK_UN); close(lock) }
        var transaction = try transactionStore.load(transactionID)
        try undo(&transaction)
    }

    private func acquireLock() throws -> Int32 {
        try FileManager.default.createDirectory(at: transactionStore.directory, withIntermediateDirectories: true)
        let fd = open(transactionStore.directory.appendingPathComponent("execution.lock").path,
                      O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw TransactionStore.posixError() }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw SafeRunError.executionFailed("Another execution or recovery is already using this recovery store.")
        }
        return fd
    }

    private func coordinate(_ action: SafeRunAction, body: () throws -> Void) throws {
        let urls = [action.sourceURL, action.destinationURL].compactMap { $0 }
        guard let first = urls.first else { throw invalidAction(action) }
        var coordinationError: NSError?
        var bodyError: Error?
        var invoked = false
        let coordinator = NSFileCoordinator()
        withoutActuallyEscaping(body) { coordinatedBody in
            if urls.count == 2 {
                coordinator.coordinate(writingItemAt: first, options: [], writingItemAt: urls[1], options: [],
                                       error: &coordinationError) { _, _ in
                    invoked = true
                    do { try coordinatedBody() } catch { bodyError = error }
                }
            } else {
                coordinator.coordinate(writingItemAt: first, options: [], error: &coordinationError) { _ in
                    invoked = true
                    do { try coordinatedBody() } catch { bodyError = error }
                }
            }
        }
        if let bodyError { throw bodyError }
        if let coordinationError { throw coordinationError }
        guard invoked else { throw SafeRunError.executionFailed("File coordination did not acquire access.") }
    }

    private func verify(_ action: SafeRunAction, root: URL, expected: [String: FileIdentity]) throws {
        for url in [action.sourceURL, action.destinationURL].compactMap({ $0 }) {
            try FileSnapshot.validatePath(url, root: root)
            guard let identity = expected[url.standardizedFileURL.path] else { throw SafeRunError.invalidPath(url) }
            try identity.requireMatch(at: url)
            try verifyParents(url, root: root, expected: expected)
        }
        if action.type == .createDirectory {
            guard action.sourceURL == nil, let destination = action.destinationURL,
                  try FileIdentity.read(destination).kind == .absent else { throw invalidAction(action) }
        } else {
            guard let source = action.sourceURL, try FileIdentity.read(source).kind == .file else { throw invalidAction(action) }
            if action.type == .deleteFile {
                guard action.destinationURL == nil else { throw invalidAction(action) }
            } else {
                guard let destination = action.destinationURL, source.standardizedFileURL != destination.standardizedFileURL,
                      try FileIdentity.read(destination).kind == (action.type == .replaceFile ? .file : .absent) else { throw invalidAction(action) }
            }
        }
    }

    private func invalidAction(_ action: SafeRunAction) -> SafeRunError {
        .planNotExecutable("Invalid \(action.type.title) action for \(action.filename). Only regular files are supported; re-simulate the plan.")
    }

    private func verifyParents(_ url: URL, root: URL, expected: [String: FileIdentity]) throws {
        var parent = url.standardizedFileURL.deletingLastPathComponent()
        while true {
            guard let identity = expected[parent.path], identity.kind == .directory else { throw SafeRunError.invalidPath(parent) }
            try identity.requireMatch(at: parent)
            if parent == root { break }
            parent.deleteLastPathComponent()
        }
    }

    private func setPhase(_ phase: ExecutionTransaction.Entry.Phase, _ index: Int,
                          _ transaction: inout ExecutionTransaction) throws {
        transaction.entries[index].phase = phase
        try transactionStore.save(transaction)
    }

    private func apply(_ index: Int, transaction: inout ExecutionTransaction) throws {
        let entry = transaction.entries[index]
        let action = entry.action
        switch action.type {
        case .copyFile, .replaceFile:
            try FileManager.default.copyItem(at: action.sourceURL!, to: entry.stagingURL)
            let staged = try FileIdentity.read(entry.stagingURL)
            guard staged.digest == entry.sourceBefore?.digest, staged.size == entry.sourceBefore?.size else { throw invalidAction(action) }
            let handle = try FileHandle(forWritingTo: entry.stagingURL)
            defer { try? handle.close() }
            try handle.synchronize()
            transaction.entries[index].installed = staged
        case .createDirectory:
            try FileManager.default.createDirectory(at: entry.stagingURL, withIntermediateDirectories: false)
            transaction.entries[index].installed = try FileIdentity.read(entry.stagingURL)
        case .moveFile, .renameFile:
            transaction.entries[index].installed = entry.sourceBefore
        case .deleteFile: break
        }
        try TransactionStore.syncDirectory(entry.stagingURL.deletingLastPathComponent())
        try setPhase(.staged, index, &transaction)
        if action.type == .deleteFile || action.type == .replaceFile {
            try setPhase(.backingUp, index, &transaction)
            let original = action.type == .deleteFile ? action.sourceURL! : action.destinationURL!
            try (action.type == .deleteFile ? entry.sourceBefore : entry.destinationBefore)!.requireMatch(at: original)
            try moveExclusively(original, entry.backupURL)
            try setPhase(.backedUp, index, &transaction)
        }
        if action.type != .deleteFile {
            try setPhase(.publishing, index, &transaction)
            let source = action.type == .moveFile || action.type == .renameFile ? action.sourceURL! : entry.stagingURL
            try transaction.entries[index].installed!.requireMatch(at: source)
            try moveExclusively(source, action.destinationURL!)
        }
        try setPhase(.applied, index, &transaction)
    }

    /// RENAME_EXCL provides an atomic no-clobber move. Cross-volume operations fail
    /// closed rather than degrading to a copy/delete pair with an untracked gap.
    private func moveExclusively(_ source: URL, _ destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw TransactionStore.posixError() }
        try TransactionStore.syncDirectory(source.deletingLastPathComponent())
        if source.deletingLastPathComponent() != destination.deletingLastPathComponent() {
            try TransactionStore.syncDirectory(destination.deletingLastPathComponent())
        }
    }

    private func undo(_ transaction: inout ExecutionTransaction) throws {
        guard transaction.state != .expired else {
            throw SafeRunError.executionFailed("Recovery data for this transaction expired and cannot be rolled back.")
        }
        if transaction.state == .rolledBack { return }
        transaction.state = .recovering
        try transactionStore.save(transaction)
        var failures: [String] = []
        for index in transaction.entries.indices.reversed() where transaction.entries[index].phase != .undone {
            do {
                try coordinate(transaction.entries[index].action) {
                    try undoEntry(index, transaction: &transaction)
                }
                transaction.entries[index].failure = nil
                try setPhase(.undone, index, &transaction)
            } catch {
                let message = "\(transaction.entries[index].action.filename): \(error.localizedDescription)"
                failures.append(message)
                transaction.entries[index].failure = message
                // Persist each failure while still trying independent earlier actions.
                try transactionStore.save(transaction)
            }
        }
        transaction.state = failures.isEmpty ? .rolledBack : .recoveryRequired
        try transactionStore.save(transaction)
        if !failures.isEmpty { throw SafeRunError.executionFailed(failures.joined(separator: "\n")) }
    }

    private func undoEntry(_ index: Int, transaction: inout ExecutionTransaction) throws {
        let entry = transaction.entries[index]
        let action = entry.action
        let root = transaction.snapshot.root
        try validateStorage(entry, transactionID: transaction.id)
        var expected = transaction.snapshot.files
        for record in transaction.entries where record.action.type == .createDirectory {
            if let destination = record.action.destinationURL, let installed = record.installed { expected[destination.standardizedFileURL.path] = installed }
        }
        for url in [action.sourceURL, action.destinationURL].compactMap({ $0 }) {
            try FileSnapshot.validatePath(url, root: root)
        }
        // No user mutation is possible before staging is recorded.
        if entry.phase == .prepared || entry.phase == .staged { return }
        try setPhase(.undoing, index, &transaction)
        switch action.type {
        case .moveFile, .renameFile:
            let source = action.sourceURL!, destination = action.destinationURL!
            if try FileIdentity.read(destination).kind == .absent {
                try entry.sourceBefore!.requireMatch(at: source)
                return
            }
            try verifyParents(destination, root: root, expected: expected)
            try verifyParents(source, root: root, expected: expected)
            try entry.installed!.requireMatch(at: destination)
            try FileIdentity.absent.requireMatch(at: source)
            try moveExclusively(destination, source)
        case .copyFile, .createDirectory:
            try removeInstalled(entry, root: root, expected: expected)
        case .deleteFile, .replaceFile:
            let original = action.type == .deleteFile ? action.sourceURL! : action.destinationURL!
            let before = (action.type == .deleteFile ? entry.sourceBefore : entry.destinationBefore)!
            if try FileIdentity.read(entry.backupURL).kind == .absent {
                // Backup was not moved, or a previous recovery already restored it.
                try before.requireMatch(at: original)
                return
            }
            try before.requireMatch(at: entry.backupURL)
            if action.type == .replaceFile { try removeInstalled(entry, root: root, expected: expected) }
            try verifyParents(original, root: root, expected: expected)
            try FileIdentity.absent.requireMatch(at: original)
            try moveExclusively(entry.backupURL, original)
        }
    }

    private func validateStorage(_ entry: ExecutionTransaction.Entry, transactionID: UUID) throws {
        let storage = recoveryDirectory.appendingPathComponent(transactionID.uuidString)
        let prefix = storage.appendingPathComponent(entry.action.id.uuidString)
        guard entry.stagingURL == prefix.appendingPathExtension("stage"),
              entry.backupURL == prefix.appendingPathExtension("backup"),
              entry.undoURL == prefix.appendingPathExtension("undo"),
              try FileIdentity.read(storage).kind == .directory,
              storage.resolvingSymlinksInPath().path == recoveryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent(transactionID.uuidString).path else {
            throw SafeRunError.executionFailed("Transaction recovery paths do not match this store.")
        }
    }

    private func removeInstalled(_ entry: ExecutionTransaction.Entry, root: URL,
                                 expected: [String: FileIdentity]) throws {
        let destination = entry.action.destinationURL!
        let current = try FileIdentity.read(destination)
        if current.kind == .absent { return }
        guard let installed = entry.installed else { throw SafeRunError.executionFailed("Installed file identity is unavailable.") }
        try installed.requireMatch(at: destination)
        try verifyParents(destination, root: root, expected: expected)
        if entry.action.type == .createDirectory {
            // rmdir is intrinsically empty-only, including when another process adds
            // a child between inspection and removal. Never recursively delete here.
            guard rmdir(destination.path) == 0 else { throw TransactionStore.posixError() }
            try TransactionStore.syncDirectory(destination.deletingLastPathComponent())
        } else {
            try moveExclusively(destination, entry.undoURL)
        }
    }
}
