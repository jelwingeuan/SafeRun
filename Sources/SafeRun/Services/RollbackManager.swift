import Foundation

struct RollbackManager: Sendable {
    func makeJournal(for plan: SafeRunPlan) -> RollbackJournal {
        let entries = plan.actions.map { action in
            let recoveryURL = action.type == .deleteFile || action.type == .replaceFile
                ? recoveryURL(for: action)
                : nil
            return RollbackJournalEntry(
                id: UUID(),
                originalActionID: action.id,
                inverseAction: inverse(of: action, recoveryURL: recoveryURL),
                recoveryURL: recoveryURL,
                note: note(for: action)
            )
        }
        return RollbackJournal(id: UUID(), planID: plan.id, rootFolder: plan.selectedRootFolder, createdAt: .now, entries: entries)
    }

    private func inverse(of action: SafeRunAction, recoveryURL: URL?) -> SafeRunAction? {
        switch action.type {
        case .moveFile, .renameFile:
            guard let source = action.sourceURL, let destination = action.destinationURL else { return nil }
            return SafeRunAction(
                type: .moveFile,
                sourceURL: destination,
                destinationURL: source,
                filename: action.filename,
                description: "Undo \(action.description)",
                risk: .medium,
                isReversible: true
            )
        case .copyFile:
            guard let destination = action.destinationURL else { return nil }
            return SafeRunAction(
                type: .deleteFile,
                sourceURL: destination,
                filename: action.filename,
                description: "Remove copied \(action.filename)",
                risk: .high,
                isReversible: true
            )
        case .createDirectory:
            guard let destination = action.destinationURL else { return nil }
            return SafeRunAction(
                type: .deleteFile,
                sourceURL: destination,
                filename: action.filename,
                description: "Remove created directory \(action.filename)",
                risk: .low,
                isReversible: true
            )
        case .deleteFile:
            guard let source = action.sourceURL, let recoveryURL else { return nil }
            return SafeRunAction(
                type: .moveFile,
                sourceURL: recoveryURL,
                destinationURL: source,
                filename: action.filename,
                description: "Restore deleted \(action.filename)",
                risk: .medium,
                isReversible: true
            )
        case .replaceFile:
            guard let destination = action.destinationURL, let recoveryURL else { return nil }
            return SafeRunAction(
                type: .replaceFile,
                sourceURL: recoveryURL,
                destinationURL: destination,
                filename: action.filename,
                description: "Restore replaced \(action.filename)",
                risk: .high,
                isReversible: true
            )
        }
    }

    func recoveryURL(for action: SafeRunAction) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SafeRun/Recovery", isDirectory: true)
            .appendingPathComponent(action.id.uuidString, isDirectory: false)
    }

    private func note(for action: SafeRunAction) -> String {
        switch action.type {
        case .deleteFile: "Deleted files are moved into recovery storage instead of being permanently removed."
        case .replaceFile: "The previous destination is preserved in recovery storage before replacement."
        default: "Inverse operation generated from the approved action."
        }
    }
}
