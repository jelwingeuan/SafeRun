import Foundation

struct SimulationEngine: Sendable {
    private let riskAnalyzer = RiskAnalyzer()

    func simulate(plan: SafeRunPlan, context: FolderContext) async -> SimulationResult {
        await Task.yield()

        var virtualEntries = Dictionary(
            context.entries.map {
                let path = PathValidator.normalized($0.url).path
                return (path, VirtualFileEntry(path: path, name: $0.name, isDirectory: $0.isDirectory, change: nil))
            },
            uniquingKeysWith: { first, _ in first }
        )
        var conflicts: [String] = []
        var warnings = plan.warnings
        var passed = 0
        var failed = 0
        var destinations: Set<String> = []

        for action in plan.actions {
            let sourcePath = action.sourceURL.map { PathValidator.normalized($0).path }
            let destinationPath = action.destinationURL.map { PathValidator.normalized($0).path }

            if let sourceURL = action.sourceURL, !PathValidator.isWithinRoot(sourceURL, root: context.rootFolder) {
                conflicts.append("\(action.filename) points outside the selected folder.")
                failed += 1
                continue
            }
            if !PathValidator.isSafeDestination(action.destinationURL, root: context.rootFolder) {
                conflicts.append("\(action.filename) has an unsafe destination path.")
                failed += 1
                continue
            }
            if let destinationURL = action.destinationURL, !PathValidator.isValidFileName(destinationURL.lastPathComponent) {
                conflicts.append("\(action.filename) has an invalid destination name.")
                failed += 1
                continue
            }
            if let destinationPath, !destinations.insert(destinationPath).inserted {
                conflicts.append("Multiple actions target \(action.destinationURL?.lastPathComponent ?? action.filename).")
                failed += 1
                continue
            }

            if let destinationURL = action.destinationURL,
               action.type != .deleteFile,
               action.type != .createDirectory {
                let parentPath = PathValidator.normalized(destinationURL.deletingLastPathComponent()).path
                let parentExists = parentPath == PathValidator.normalized(context.rootFolder).path
                    || virtualEntries[parentPath]?.isDirectory == true
                if !parentExists {
                    conflicts.append("The destination folder for \(action.filename) does not exist.")
                    failed += 1
                    continue
                }
            }

            switch action.type {
            case .createDirectory:
                guard let destinationPath else {
                    conflicts.append("The directory action for \(action.filename) has no destination.")
                    failed += 1
                    continue
                }
                if let existing = virtualEntries[destinationPath], !existing.isDirectory {
                    conflicts.append("A file already exists where \(action.filename) should be created.")
                    failed += 1
                    continue
                }
                virtualEntries[destinationPath] = VirtualFileEntry(path: destinationPath, name: action.filename, isDirectory: true, change: "created")
                passed += 1

            case .moveFile, .renameFile, .copyFile, .replaceFile, .deleteFile:
                guard let sourcePath, virtualEntries[sourcePath] != nil else {
                    conflicts.append("The source for \(action.filename) is missing.")
                    failed += 1
                    continue
                }

                if action.type == .deleteFile {
                    virtualEntries[sourcePath] = nil
                    passed += 1
                    continue
                }

                guard let destinationPath else {
                    conflicts.append("The action for \(action.filename) has no destination.")
                    failed += 1
                    continue
                }

                let destinationExists = virtualEntries[destinationPath] != nil
                if destinationExists && action.type != .replaceFile {
                    conflicts.append("A file already exists at \(destinationPath).")
                    failed += 1
                    continue
                }
                if destinationExists && action.type == .replaceFile {
                    warnings.append("\(action.filename) will replace an existing file; SafeRun will require recovery storage before execution.")
                }

                let current = virtualEntries[sourcePath]!
                if action.type != .copyFile {
                    virtualEntries[sourcePath] = nil
                }
                virtualEntries[destinationPath] = VirtualFileEntry(
                    path: destinationPath,
                    name: action.destinationURL?.lastPathComponent ?? current.name,
                    isDirectory: current.isDirectory,
                    change: action.type == .renameFile ? "renamed" : (action.type == .replaceFile ? "replaced" : "moved")
                )
                passed += 1
            }
        }

        let overallRisk = riskAnalyzer.overallRisk(for: plan.actions, context: context)
        let canExecute = failed == 0 && conflicts.isEmpty && overallRisk < .critical
        return SimulationResult(
            success: failed == 0,
            actionsPassed: passed,
            actionsFailed: failed,
            conflicts: conflicts,
            warnings: warnings,
            resultingVirtualFilesystem: virtualEntries.values.sorted { $0.path < $1.path },
            overallRisk: overallRisk,
            canExecute: canExecute
        )
    }
}
