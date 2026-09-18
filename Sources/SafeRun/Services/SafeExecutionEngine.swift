import Foundation

struct SafeExecutionEngine: Sendable {
    private let rollbackManager = RollbackManager()

    func validateApproval(plan: SafeRunPlan, simulation: SimulationResult, userApproved: Bool) throws {
        guard userApproved else {
            throw SafeRunError.executionUnavailable
        }
        guard plan.status == .simulationComplete || plan.status == .approved else {
            throw SafeRunError.planNotExecutable("SafeRun requires a completed simulation before execution.")
        }
        guard simulation.canExecute else {
            throw SafeRunError.planNotExecutable("Resolve the listed conflicts before running this plan.")
        }
    }

    func execute(
        plan: SafeRunPlan,
        simulation: SimulationResult,
        userApproved: Bool,
        onProgress: @escaping @Sendable (ExecutionProgress) async -> Void = { _ in }
    ) async throws -> ExecutionReport {
        try validateApproval(plan: plan, simulation: simulation, userApproved: userApproved)

        let root = PathValidator.normalized(plan.selectedRootFolder)
        try preflight(plan: plan, root: root)

        let journal = rollbackManager.makeJournal(for: plan)
        try prepareRecoveryStorage(for: journal)

        var completedActionIDs: [UUID] = []

        do {
            for (index, action) in plan.actions.enumerated() {
                try Task.checkCancellation()
                guard let journalEntry = journal.entries.first(where: { $0.originalActionID == action.id }) else {
                    throw SafeRunError.executionFailed("SafeRun could not create a rollback record for \(action.filename).")
                }

                try apply(action, journalEntry: journalEntry, root: root)
                completedActionIDs.append(action.id)
                await onProgress(
                    ExecutionProgress(
                        completedActions: index + 1,
                        totalActions: plan.actions.count,
                        currentAction: action.description
                    )
                )
                await Task.yield()
            }
        } catch is CancellationError {
            try rollback(journal: journal, completedActionIDs: Set(completedActionIDs), root: root)
            throw CancellationError()
        } catch {
            do {
                try rollback(journal: journal, completedActionIDs: Set(completedActionIDs), root: root)
            } catch {
                throw SafeRunError.executionFailed(
                    "Execution stopped and automatic rollback also failed: \(error.localizedDescription)"
                )
            }
            throw SafeRunError.executionFailed(
                "Execution stopped safely. Completed changes were rolled back: \(error.localizedDescription)"
            )
        }

        return ExecutionReport(journal: journal, completedActionIDs: completedActionIDs)
    }

    func rollback(_ journal: RollbackJournal) async throws {
        let root = PathValidator.normalized(journal.rootFolder)
        try rollback(
            journal: journal,
            completedActionIDs: Set(journal.entries.map(\.originalActionID)),
            root: root
        )
    }

    private func preflight(plan: SafeRunPlan, root: URL) throws {
        guard isDirectory(root) else {
            throw SafeRunError.accessDenied(root)
        }

        for action in plan.actions {
            if let source = action.sourceURL {
                try validateRootPath(source, root: root, action: action)
            } else if action.type != .createDirectory {
                throw SafeRunError.planNotExecutable("The \(action.type.title.lowercased()) action for \(action.filename) has no source.")
            }

            if let destination = action.destinationURL {
                try validateRootPath(destination, root: root, action: action)
            } else if action.type != .deleteFile {
                throw SafeRunError.planNotExecutable("The \(action.type.title.lowercased()) action for \(action.filename) has no destination.")
            }

            if let source = action.sourceURL, let destination = action.destinationURL,
               PathValidator.normalized(source) == PathValidator.normalized(destination) {
                throw SafeRunError.planNotExecutable("The action for \(action.filename) has the same source and destination.")
            }
        }
    }

    private func apply(_ action: SafeRunAction, journalEntry: RollbackJournalEntry, root: URL) throws {
        if let source = action.sourceURL {
            try validateRootPath(source, root: root, action: action)
        }
        if let destination = action.destinationURL {
            try validateRootPath(destination, root: root, action: action)
        }

        switch action.type {
        case .createDirectory:
            guard let destination = action.destinationURL else {
                throw SafeRunError.planNotExecutable("The directory action for \(action.filename) has no destination.")
            }
            try ensureParentDirectory(for: destination, root: root)
            guard !exists(destination) else {
                throw SafeRunError.planNotExecutable("The folder \(action.filename) already exists. Re-simulate before running this plan.")
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        case .moveFile, .renameFile:
            guard let source = action.sourceURL, let destination = action.destinationURL else {
                throw SafeRunError.planNotExecutable("The action for \(action.filename) is missing a path.")
            }
            try requireSource(source, root: root)
            try ensureDestinationIsAvailable(destination, root: root)
            try FileManager.default.moveItem(at: source, to: destination)

        case .copyFile:
            guard let source = action.sourceURL, let destination = action.destinationURL else {
                throw SafeRunError.planNotExecutable("The copy action for \(action.filename) is missing a path.")
            }
            try requireSource(source, root: root)
            try ensureDestinationIsAvailable(destination, root: root)
            try FileManager.default.copyItem(at: source, to: destination)

        case .deleteFile:
            guard let source = action.sourceURL, let recoveryURL = journalEntry.recoveryURL else {
                throw SafeRunError.planNotExecutable("SafeRun could not prepare recovery storage for \(action.filename).")
            }
            try requireSource(source, root: root)
            try prepareRecoveryDirectory(for: recoveryURL)
            try FileManager.default.moveItem(at: source, to: recoveryURL)

        case .replaceFile:
            guard let source = action.sourceURL,
                  let destination = action.destinationURL,
                  let recoveryURL = journalEntry.recoveryURL else {
                throw SafeRunError.planNotExecutable("SafeRun could not prepare recovery storage for \(action.filename).")
            }
            try requireSource(source, root: root)
            try requireExistingDestination(destination, root: root)
            try prepareRecoveryDirectory(for: recoveryURL)
            try FileManager.default.moveItem(at: destination, to: recoveryURL)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                if !exists(destination), exists(recoveryURL) {
                    try? FileManager.default.moveItem(at: recoveryURL, to: destination)
                }
                throw error
            }
        }
    }

    private func rollback(
        journal: RollbackJournal,
        completedActionIDs: Set<UUID>,
        root: URL
    ) throws {
        for entry in journal.entries.reversed() where completedActionIDs.contains(entry.originalActionID) {
            guard let inverseAction = entry.inverseAction else { continue }
            try applyRollback(inverseAction, root: root)
        }

        for entry in journal.entries {
            if let recoveryURL = entry.recoveryURL {
                try? FileManager.default.removeItem(at: recoveryURL)
            }
        }
    }

    private func applyRollback(_ action: SafeRunAction, root: URL) throws {
        switch action.type {
        case .deleteFile:
            guard let source = action.sourceURL else { return }
            try validateRootPath(source, root: root, action: action)
            guard exists(source) else { return }
            try FileManager.default.removeItem(at: source)

        case .moveFile, .renameFile:
            guard let source = action.sourceURL, let destination = action.destinationURL else { return }
            try validateRootPath(destination, root: root, action: action)
            guard isRecoveryPath(source) || PathValidator.isWithinRoot(source, root: root) else {
                throw SafeRunError.invalidPath(source)
            }
            guard exists(source) else {
                throw SafeRunError.planNotExecutable("Rollback storage is missing \(action.filename).")
            }
            try ensureParentDirectory(for: destination, root: root)
            guard !exists(destination) else {
                throw SafeRunError.planNotExecutable("Rollback destination already exists: \(destination.path)")
            }
            try FileManager.default.moveItem(at: source, to: destination)

        case .replaceFile:
            guard let source = action.sourceURL, let destination = action.destinationURL else { return }
            try validateRootPath(destination, root: root, action: action)
            guard isRecoveryPath(source), exists(source) else {
                throw SafeRunError.planNotExecutable("Rollback storage is missing \(action.filename).")
            }
            try ensureParentDirectory(for: destination, root: root)
            if exists(destination) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)

        case .createDirectory, .copyFile:
            throw SafeRunError.planNotExecutable("SafeRun cannot apply this rollback action: \(action.description).")
        }
    }

    private func validateRootPath(_ url: URL, root: URL, action: SafeRunAction) throws {
        guard PathValidator.isWithinRoot(url, root: root),
              PathValidator.isValidFileName(url.lastPathComponent),
              PathValidator.normalized(url) != root else {
            throw SafeRunError.invalidPath(url)
        }
        if isSymbolicLink(url) {
            throw SafeRunError.planNotExecutable("SafeRun will not mutate the symbolic link \(action.filename). Re-simulate after resolving it.")
        }
    }

    private func requireSource(_ source: URL, root: URL) throws {
        guard exists(source) else {
            throw SafeRunError.planNotExecutable("The source no longer exists: \(source.lastPathComponent). Re-simulate before running this plan.")
        }
        guard !isSymbolicLink(source) else {
            throw SafeRunError.planNotExecutable("SafeRun will not mutate a symbolic link: \(source.lastPathComponent).")
        }
        try ensureParentDirectory(for: source, root: root)
    }

    private func requireExistingDestination(_ destination: URL, root: URL) throws {
        try validateDestinationParent(destination, root: root)
        guard exists(destination) else {
            throw SafeRunError.planNotExecutable("The replacement destination no longer exists: \(destination.lastPathComponent).")
        }
        guard !isSymbolicLink(destination) else {
            throw SafeRunError.planNotExecutable("SafeRun will not replace a symbolic link: \(destination.lastPathComponent).")
        }
    }

    private func ensureDestinationIsAvailable(_ destination: URL, root: URL) throws {
        try validateDestinationParent(destination, root: root)
        guard !exists(destination) else {
            throw SafeRunError.planNotExecutable("The destination already exists: \(destination.lastPathComponent). Re-simulate before running this plan.")
        }
    }

    private func ensureParentDirectory(for url: URL, root: URL) throws {
        try validateDestinationParent(url, root: root)
    }

    private func validateDestinationParent(_ url: URL, root: URL) throws {
        let parent = PathValidator.normalized(url.deletingLastPathComponent())
        guard PathValidator.isWithinRoot(parent, root: root), isDirectory(parent) else {
            throw SafeRunError.planNotExecutable("The destination folder is missing: \(parent.lastPathComponent).")
        }
        guard !isSymbolicLink(parent) else {
            throw SafeRunError.planNotExecutable("SafeRun will not mutate through a symbolic-link folder: \(parent.lastPathComponent).")
        }
    }

    private func prepareRecoveryStorage(for journal: RollbackJournal) throws {
        for entry in journal.entries {
            if let recoveryURL = entry.recoveryURL {
                try prepareRecoveryDirectory(for: recoveryURL)
            }
        }
    }

    private func prepareRecoveryDirectory(for recoveryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: recoveryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !exists(recoveryURL) else {
            throw SafeRunError.planNotExecutable("Recovery storage already contains \(recoveryURL.lastPathComponent).")
        }
    }

    private func isRecoveryPath(_ url: URL) -> Bool {
        PathValidator.isWithinRoot(url, root: recoveryDirectoryURL)
    }

    private var recoveryDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SafeRun/Recovery", isDirectory: true)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
