import AppKit
import Combine
import Foundation

@MainActor
final class SafeRunViewModel: ObservableObject {
    @Published var selectedSection: AppSection = .dashboard
    @Published var selectedFolder: URL?
    @Published var folderContext: FolderContext?
    @Published var instruction = ""
    @Published var plan: SafeRunPlan?
    @Published var simulationResult: SimulationResult?
    @Published var selectedActionID: UUID?
    @Published var isActionInspectorPresented = false
    @Published var historyItems: [RunHistoryItem] = []
    @Published var isScanning = false
    @Published var isAnalyzing = false
    @Published var isSimulating = false
    @Published var isExecuting = false
    @Published var executionProgress = 0.0
    @Published var executionStatus = ""
    @Published var rollbackJournals: [RollbackJournal] = []
    @Published var isRollingBack = false
    @Published var errorMessage: String?

    private let scanner = FolderContextScanner()
    private let planner = MockAutomationPlanner()
    private let simulationEngine = SimulationEngine()
    private let executionEngine = SafeExecutionEngine()
    private let historyStore = RunHistoryStore()
    private let rollbackStore = RollbackStore()
    private let folderAccessStore = FolderAccessStore()
    private var scanTask: Task<Void, Never>?

    init() {
        Task { [weak self] in
            guard let self else { return }
            historyItems = await historyStore.load()
            rollbackJournals = await rollbackStore.load()
        }
    }

    var canAnalyze: Bool {
        folderContext != nil
            && !isScanning
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isAnalyzing
    }

    var selectedAction: SafeRunAction? {
        guard let selectedActionID else { return nil }
        return plan?.actions.first { $0.id == selectedActionID }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "SafeRun only previews and works inside the folder you choose."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        acceptFolder(url)
    }

    func acceptDroppedFolder(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = SafeRunError.selectedItemIsNotDirectory.localizedDescription
            return
        }
        acceptFolder(url)
    }

    func acceptFolder(_ url: URL) {
        do {
            let accessibleURL = try folderAccessStore.grantAccess(to: url)
            selectFolder(accessibleURL)
        } catch {
            errorMessage = SafeRunError.accessDenied(url).localizedDescription
        }
    }

    func openSimulation(_ item: RunHistoryItem) {
        do {
            let accessibleURL = try folderAccessStore.restoreAccess(to: item.selectedDirectory)
            selectFolder(accessibleURL)
            instruction = item.instruction
            selectedSection = .dashboard
        } catch {
            errorMessage = SafeRunError.accessDenied(item.selectedDirectory).localizedDescription
        }
    }

    private func selectFolder(_ url: URL) {
        let normalizedURL = PathValidator.normalized(url)
        selectedFolder = normalizedURL
        folderContext = nil
        plan = nil
        simulationResult = nil
        selectedActionID = nil
        isActionInspectorPresented = false
        errorMessage = nil
        scanTask?.cancel()
        isScanning = true

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = try await scanner.scan(root: normalizedURL)
                folderContext = context
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    func analyze() {
        guard let folderContext else {
            errorMessage = SafeRunError.folderNotFound.localizedDescription
            return
        }
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = SafeRunError.emptyInstruction.localizedDescription
            return
        }

        errorMessage = nil
        isAnalyzing = true
        simulationResult = nil
        selectedActionID = nil
        isActionInspectorPresented = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let generatedPlan = try await planner.generatePlan(instruction: instruction, folderContext: folderContext)
                plan = generatedPlan
                selectedSection = .simulations
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    func simulate() {
        guard var plan, let folderContext else { return }
        errorMessage = nil
        isSimulating = true
        plan.status = .simulating
        self.plan = plan

        Task { [weak self] in
            guard let self else { return }
            let result = await simulationEngine.simulate(plan: plan, context: folderContext)
            simulationResult = result
            var completedPlan = plan
            completedPlan.status = .simulationComplete
            completedPlan.conflicts = result.conflicts
            completedPlan.warnings = result.warnings
            completedPlan.actions = completedPlan.actions.map { action in
                var action = action
                action.validationStatus = result.conflicts.contains(where: { $0.localizedCaseInsensitiveContains(action.filename) }) ? .failed : .passed
                action.conflictStatus = action.validationStatus == .failed ? .unresolved : .none
                return action
            }
            self.plan = completedPlan
            isSimulating = false
            await saveHistory(for: completedPlan, result: result)
        }
    }

    func selectAction(_ action: SafeRunAction) {
        selectedActionID = action.id
        isActionInspectorPresented = true
    }

    func cancelCurrentPlan() {
        plan = nil
        simulationResult = nil
        selectedActionID = nil
        isActionInspectorPresented = false
        selectedSection = .dashboard
    }

    func editCurrentPlan() {
        guard var plan else { return }
        plan.status = .ready
        plan.conflicts = []
        plan.actions = plan.actions.map { action in
            var action = action
            action.validationStatus = .pending
            action.conflictStatus = .none
            return action
        }
        self.plan = plan
        simulationResult = nil
    }

    func executeCurrentPlan() {
        guard let plan, let simulationResult else { return }
        guard !isExecuting else { return }
        let maximumAutomaticActions = UserDefaults.standard.integer(forKey: "maximumAutomaticActions")
        let actionLimit = maximumAutomaticActions > 0 ? maximumAutomaticActions : 100
        guard plan.totalOperations <= actionLimit else {
            errorMessage = "This plan contains \(plan.totalOperations) actions, above the configured limit of \(actionLimit). Increase the limit in Settings or edit the plan."
            return
        }

        var executingPlan = plan
        executingPlan.status = .executing
        self.plan = executingPlan
        isExecuting = true
        executionProgress = 0
        executionStatus = "Preparing recovery storage…"
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let report = try await executionEngine.execute(
                    plan: plan,
                    simulation: simulationResult,
                    userApproved: true
                ) { [weak self] progress in
                    await self?.updateExecutionProgress(progress)
                }

                var completedPlan = executingPlan
                completedPlan.status = .completed
                let completedIDs = Set(report.completedActionIDs)
                completedPlan.actions = completedPlan.actions.map { action in
                    var action = action
                    if completedIDs.contains(action.id) {
                        action.executionState = .completed
                    }
                    return action
                }
                self.plan = completedPlan
                self.rollbackJournals.insert(report.journal, at: 0)
                self.isExecuting = false
                self.executionProgress = 1
                self.executionStatus = "Completed successfully"

                do {
                    try await rollbackStore.append(report.journal)
                    try await updateHistory(plan: completedPlan, result: "Completed successfully", rollbackAvailable: true)
                } catch {
                    self.errorMessage = "The files were changed successfully, but SafeRun could not save the rollback journal: \(error.localizedDescription)"
                }
            } catch is CancellationError {
                self.isExecuting = false
                self.executionProgress = 0
                self.executionStatus = "Execution cancelled and rolled back"
                if var currentPlan = self.plan {
                    currentPlan.status = .simulationComplete
                    self.plan = currentPlan
                }
            } catch {
                self.isExecuting = false
                self.executionProgress = 0
                self.executionStatus = "Execution failed and was rolled back"
                if var currentPlan = self.plan {
                    currentPlan.status = .failed
                    self.plan = currentPlan
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func rollback(_ journal: RollbackJournal) {
        guard !isRollingBack else { return }
        isRollingBack = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try folderAccessStore.restoreAccess(to: journal.rootFolder)
                try await executionEngine.rollback(journal)
                try await rollbackStore.remove(journal.id)
                rollbackJournals.removeAll { $0.id == journal.id }
                if var currentPlan = plan, currentPlan.id == journal.planID {
                    currentPlan.status = .rolledBack
                    self.plan = currentPlan
                }
                try await updateHistory(planID: journal.planID, result: "Rolled back", rollbackAvailable: false)
            } catch {
                errorMessage = "SafeRun could not complete the rollback: \(error.localizedDescription)"
            }
            isRollingBack = false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func saveHistory(for plan: SafeRunPlan, result: SimulationResult) async {
        let item = RunHistoryItem(
            id: plan.id,
            timestamp: .now,
            instruction: plan.originalInstruction,
            selectedDirectory: plan.selectedRootFolder,
            operationCount: plan.totalOperations,
            risk: result.overallRisk,
            result: result.conflicts.isEmpty ? "Simulation ready" : "Needs review",
            rollbackAvailable: false
        )
        do {
            try await historyStore.append(item)
            historyItems = await historyStore.load()
        } catch {
            errorMessage = "The plan was created, but SafeRun could not save it to local history."
        }
    }

    private func updateExecutionProgress(_ progress: ExecutionProgress) {
        executionProgress = progress.totalActions == 0
            ? 1
            : Double(progress.completedActions) / Double(progress.totalActions)
        executionStatus = progress.currentAction
    }

    private func updateHistory(
        plan: SafeRunPlan,
        result: String,
        rollbackAvailable: Bool
    ) async throws {
        try await updateHistory(planID: plan.id, result: result, rollbackAvailable: rollbackAvailable, fallbackPlan: plan)
    }

    private func updateHistory(
        planID: UUID,
        result: String,
        rollbackAvailable: Bool,
        fallbackPlan: SafeRunPlan? = nil
    ) async throws {
        guard let existing = historyItems.first(where: { $0.id == planID }) else {
            guard let fallbackPlan else { return }
            let fallback = RunHistoryItem(
                id: fallbackPlan.id,
                timestamp: .now,
                instruction: fallbackPlan.originalInstruction,
                selectedDirectory: fallbackPlan.selectedRootFolder,
                operationCount: fallbackPlan.totalOperations,
                risk: fallbackPlan.overallRisk,
                result: result,
                rollbackAvailable: rollbackAvailable
            )
            try await historyStore.update(fallback)
            historyItems = await historyStore.load()
            return
        }

        let updated = RunHistoryItem(
            id: existing.id,
            timestamp: existing.timestamp,
            instruction: existing.instruction,
            selectedDirectory: existing.selectedDirectory,
            operationCount: existing.operationCount,
            risk: existing.risk,
            result: result,
            rollbackAvailable: rollbackAvailable
        )
        try await historyStore.update(updated)
        historyItems = await historyStore.load()
    }
}
