import Foundation

struct SimulationEngine: Sendable {
    @concurrent
    func simulate(
        plan: SafeRunPlan, context: FolderContext,
        onProgress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> SimulationResult {
        var entries = Dictionary(context.entries.map {
            (PlanValidator.collisionKey($0.url), VirtualFileEntry(path: $0.url.path, name: $0.name, isDirectory: $0.isDirectory, change: nil))
        }, uniquingKeysWith: { first, _ in first })
        var conflicts: [String] = []
        var warnings = plan.warnings + (context.scanWarnings ?? [])
        var passed = 0
        var destinations = Set<String>()
        var sources = Set<String>()
        var snapshot: FileSnapshot?
        do {
            _ = try PlanValidator().validate(plan: plan, context: context, maximumActions: 500)
            snapshot = try FileSnapshot.capture(plan: plan)
        } catch {
            conflicts.append("The plan failed safety validation: \(error.localizedDescription)")
        }
        let rootKey = PlanValidator.collisionKey(context.rootFolder)
        if conflicts.isEmpty {
            for (index, action) in plan.actions.enumerated() {
                if Task.isCancelled { conflicts.append("Simulation cancelled. Simulate again before running."); break }
                do {
                    let source = action.sourceURL.map(PlanValidator.collisionKey)
                    let destination = action.destinationURL.map(PlanValidator.collisionKey)
                    if let source, !sources.insert(source).inserted {
                        throw SafeRunError.planNotExecutable("Multiple operations use \(action.filename). Split this into separate plans.")
                    }
                    if let destination {
                        guard destinations.insert(destination).inserted else {
                            throw SafeRunError.planNotExecutable("Multiple actions target \(action.filename), including case or Unicode variants.")
                        }
                        let parent = PlanValidator.collisionKey(action.destinationURL!.deletingLastPathComponent())
                        guard parent == rootKey || entries[parent]?.isDirectory == true else {
                            throw SafeRunError.planNotExecutable("The destination folder for \(action.filename) does not exist.")
                        }
                        if action.type == .replaceFile {
                            guard entries[destination] != nil, entries[destination]?.isDirectory == false else {
                                throw SafeRunError.planNotExecutable("The replacement target for \(action.filename) is missing or is a folder.")
                            }
                        } else if entries[destination] != nil {
                            throw SafeRunError.planNotExecutable("A file or folder already exists at the destination of \(action.filename), including case or Unicode variants.")
                        }
                    }
                    if action.type == .createDirectory, let destination {
                        entries[destination] = VirtualFileEntry(path: action.destinationURL!.path, name: action.filename, isDirectory: true, change: "created")
                    } else {
                        guard let source, let current = entries[source], !current.isDirectory else {
                            throw SafeRunError.planNotExecutable("The source for \(action.filename) is missing or is a folder.")
                        }
                        if action.type == .deleteFile || action.type == .moveFile || action.type == .renameFile { entries[source] = nil }
                        if let destination {
                            entries[destination] = VirtualFileEntry(path: action.destinationURL!.path, name: action.destinationURL!.lastPathComponent, isDirectory: false, change: action.type.rawValue)
                        }
                        if action.type == .deleteFile || action.type == .replaceFile {
                            warnings.append("\(action.filename): previous content will be preserved in recovery storage.")
                        }
                    }
                    passed += 1
                } catch { conflicts.append(error.localizedDescription) }
                await onProgress(index + 1, plan.actions.count)
            }
        }
        let risk = RiskAnalyzer().overallRisk(for: plan.actions, context: context)
        let success = conflicts.isEmpty && passed == plan.actions.count
        SafeRunLog.simulation.info("Simulation finished: \(passed) actions passed, \(conflicts.count) conflicts")
        return SimulationResult(
            success: success, actionsPassed: passed, actionsFailed: plan.actions.count - passed,
            conflicts: conflicts, warnings: warnings,
            resultingVirtualFilesystem: entries.values.sorted { $0.path < $1.path },
            overallRisk: risk, canExecute: success && !plan.actions.isEmpty && risk < .critical && snapshot != nil,
            snapshot: snapshot
        )
    }
}
