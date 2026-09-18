import Foundation

/// The model's risk and permission claims are never used as authority.
struct PlanValidator: Sendable {
    func validate(plan: SafeRunPlan, context: FolderContext, maximumActions: Int = 100) throws -> SafeRunPlan {
        guard PathValidator.normalized(plan.selectedRootFolder) == PathValidator.normalized(context.rootFolder),
              !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              plan.actions.count <= min(max(maximumActions, 1), 500),
              Set(plan.actions.map(\.id)).count == plan.actions.count else {
            throw SafeRunError.planNotExecutable("The plan has an invalid root, title, duplicate action identifiers, or exceeds the action limit. Generate a smaller plan.")
        }
        var validated = plan
        for index in validated.actions.indices {
            var action = validated.actions[index]
            action.validationStatus = .pending
            action.conflictStatus = .none
            if let confidence = action.confidence, !(0...1).contains(confidence) {
                throw SafeRunError.planNotExecutable("The planner returned invalid confidence values. Generate the plan again.")
            }
            switch action.type {
            case .createDirectory:
                guard action.sourceURL == nil, action.destinationURL != nil else { throw invalid(action) }
            case .deleteFile:
                guard action.sourceURL != nil, action.destinationURL == nil else { throw invalid(action) }
            default:
                guard action.sourceURL != nil, action.destinationURL != nil else { throw invalid(action) }
            }
            for url in [action.sourceURL, action.destinationURL].compactMap({ $0 }) {
                try Self.validatePath(url, root: context.rootFolder)
            }
            if let source = action.sourceURL {
                // V1 deliberately limits mutations to existing regular files; no recursive directory moves/deletes.
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, values.isAliasFile != true else {
                    throw SafeRunError.planNotExecutable("Only regular files can be moved, copied, renamed, deleted, or replaced in SafeRun 1.0: \(action.filename).")
                }
                if let destination = action.destinationURL,
                   Self.collisionKey(source) == Self.collisionKey(destination) { throw invalid(action) }
                if action.type == .renameFile,
                   source.deletingLastPathComponent() != action.destinationURL?.deletingLastPathComponent() {
                    throw SafeRunError.planNotExecutable("A rename must keep the file in the same folder. Use a move instead.")
                }
            }
            if action.type == .replaceFile, let destination = action.destinationURL {
                let values = try destination.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { throw invalid(action) }
            }
            validated.actions[index].risk = RiskAnalyzer().risk(for: action, context: context)
            validated.actions[index].isReversible = true
        }
        return validated
    }

    static func validatePath(_ url: URL, root: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              !url.pathComponents.contains(".."), !url.path.contains("\0"),
              PathValidator.isWithinRoot(url, root: root),
              PathValidator.normalized(url) != PathValidator.normalized(root) else {
            throw SafeRunError.invalidPath(url)
        }
        // Inspect the lexical path, not just the resolved path: even an in-root symlink/alias is blocked.
        var current = url.standardizedFileURL
        let boundary = root.standardizedFileURL
        while current.path != boundary.path && current.path != "/" {
            if let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey, .isPackageKey]),
               values.isSymbolicLink == true || values.isAliasFile == true || values.isPackage == true {
                throw SafeRunError.invalidPath(url)
            }
            current.deleteLastPathComponent()
        }
    }

    static func collisionKey(_ url: URL) -> String {
        // Conservatively reject case/Unicode collisions even on case-sensitive volumes.
        url.standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func invalid(_ action: SafeRunAction) -> SafeRunError {
        .planNotExecutable("The \(action.type.title.lowercased()) operation for \(action.filename) has invalid source or destination paths.")
    }
}
