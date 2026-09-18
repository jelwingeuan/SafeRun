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
    @Published var hasAPIKey = false
    @Published var maskedAPIKey = "Not connected"
    @Published var connectionStatus = ""
    @Published var isTestingConnection = false
    @Published var isOnboardingPresented = !UserDefaults.standard.bool(forKey: "onboardingCompleted")
    @Published var recoveryBytes: Int64 = 0
    @Published var scannedEntries = 0
    @Published var simulationProgress = 0.0
    @Published var changedPaths: [String] = []
    @Published var interruptedTransactions: [ExecutionTransaction] = []

    private let scanner = FolderContextScanner()
    private let apiKeyManager = APIKeyManager()
    private let simulationEngine = SimulationEngine()
    private let executionEngine = SafeExecutionEngine()
    private let historyStore = RunHistoryStore()
    private let rollbackStore = RollbackStore()
    private let folderAccessStore = FolderAccessStore()
    private var scanTask: Task<Void, Never>?
    private var planningTask: Task<Void, Never>?
    private var simulationTask: Task<Void, Never>?

    init() {
        refreshAPIKeyStatus()
        Task { [weak self] in
            guard let self else { return }
            historyItems = await historyStore.load()
            await refreshRecovery()
        }
    }

    var isBusy: Bool { isScanning || isAnalyzing || isSimulating || isExecuting || isRollingBack }

    private var actionLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: "maximumAutomaticActions")
        return min(max(stored == 0 ? 100 : stored, 1), 500)
    }

    private var planner: OpenAIPlanner {
        OpenAIPlanner(apiKeyManager: apiKeyManager,
                      model: PlannerModel(rawValue: UserDefaults.standard.string(forKey: "plannerModel") ?? "") ?? .defaultModel,
                      maximumActions: actionLimit)
    }

    var canAnalyze: Bool {
        folderContext != nil
            && hasAPIKey && !isBusy
            && !isScanning
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isAnalyzing
    }

    var selectedAction: SafeRunAction? {
        guard let selectedActionID else { return nil }
        return plan?.actions.first { $0.id == selectedActionID }
    }

    func chooseFolder() {
        guard !isBusy else { return }
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
        guard !isBusy else { return }
        do {
            let accessibleURL = try folderAccessStore.grantAccess(to: url)
            selectFolder(accessibleURL)
        } catch {
            errorMessage = SafeRunError.accessDenied(url).localizedDescription
        }
    }

    func openSimulation(_ item: RunHistoryItem) {
        guard !isBusy else { return }
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
        scannedEntries = 0

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = try await scanner.scan(root: normalizedURL) { [weak self] count in
                    await self?.updateScanProgress(count)
                }
                try Task.checkCancellation()
                folderContext = context
            } catch is CancellationError {
                isScanning = false
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    func analyze() {
        guard !isBusy else { return }
        guard hasAPIKey else {
            selectedSection = .settings
            errorMessage = "Connect AI to create your first SafeRun automation."
            return
        }
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

        planningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let generatedPlan = try await planner.generatePlan(instruction: instruction, folderContext: folderContext)
                try Task.checkCancellation()
                plan = generatedPlan
                selectedSection = .simulations
                SafeRunLog.planner.info("Validated AI plan received")
            } catch is CancellationError {
                isAnalyzing = false
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    func simulate() {
        guard !isBusy, var plan else { return }
        errorMessage = nil
        changedPaths = []
        simulationProgress = 0
        simulationResult = nil
        isSimulating = true
        plan.status = .simulating
        self.plan = plan

        simulationTask = Task { [weak self] in
            guard let self else { return }
            defer { isSimulating = false }
            do {
            try restoreExactAccess(to: plan.selectedRootFolder)
            let context = try await scanner.scan(root: plan.selectedRootFolder)
            _ = try PlanValidator().validate(plan: plan, context: context, maximumActions: actionLimit)
            folderContext = context
            let result = await simulationEngine.simulate(plan: plan, context: context) { [weak self] completed, total in
                await self?.updateSimulationProgress(completed, total: total)
            }
            try Task.checkCancellation()
            simulationResult = result
            var completedPlan = plan
            completedPlan.status = .simulationComplete
            completedPlan.conflicts = result.conflicts
            completedPlan.warnings = result.warnings
            completedPlan.actions = completedPlan.actions.map { action in
                var action = action
                action.validationStatus = result.success ? .passed : .failed
                action.conflictStatus = action.validationStatus == .failed ? .unresolved : .none
                return action
            }
            self.plan = completedPlan
            isSimulating = false
            await saveHistory(for: completedPlan, result: result)
            } catch is CancellationError {
                self.plan?.status = .ready
            } catch {
                self.plan?.status = .ready
                errorMessage = "Simulation could not validate this plan. \(error.localizedDescription)"
            }
        }
    }

    func selectAction(_ action: SafeRunAction) {
        selectedActionID = action.id
        isActionInspectorPresented = true
    }

    func cancelCurrentPlan() {
        guard !isBusy else { return }
        plan = nil
        simulationResult = nil
        selectedActionID = nil
        isActionInspectorPresented = false
        selectedSection = .dashboard
    }

    func editCurrentPlan() {
        guard !isBusy else { return }
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
        guard !isBusy else { return }
        guard plan.status != .completed, plan.status != .rolledBack else { return }
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
                try restoreExactAccess(to: plan.selectedRootFolder)
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
            } catch let stale as StalePlanError {
                isExecuting = false
                self.simulationResult = nil
                self.plan?.status = .ready
                changedPaths = stale.changedPaths
                executionStatus = "Folder Changed Since Simulation"
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
                self.executionStatus = "Execution stopped — inspect recovery status"
                if var currentPlan = self.plan {
                    currentPlan.status = .failed
                    self.plan = currentPlan
                }
                self.errorMessage = error.localizedDescription
            }
            await refreshRecovery()
        }
    }

    func rollback(_ journal: RollbackJournal) {
        guard !isBusy else { return }
        isRollingBack = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try restoreExactAccess(to: journal.rootFolder)
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
            await refreshRecovery()
        }
    }

    func saveAPIKey(_ key: String) {
        guard !isTestingConnection, !isAnalyzing else { return }
        do {
            if try apiKeyManager.retrieve() == nil { try apiKeyManager.save(key) }
            else { try apiKeyManager.replace(key) }
            refreshAPIKeyStatus()
            connectionStatus = "Key saved in Keychain. Test Connection to check model access."
        } catch { connectionStatus = error.localizedDescription }
    }

    func removeAPIKey() {
        guard !isTestingConnection, !isAnalyzing else { return }
        do {
            try apiKeyManager.delete()
            refreshAPIKeyStatus()
            connectionStatus = "API key removed. History and rollback remain available."
        } catch { connectionStatus = error.localizedDescription }
    }

    func testAIConnection() {
        guard !isTestingConnection, hasAPIKey else { return }
        isTestingConnection = true
        let connectionPlanner = planner
        Task {
            defer { isTestingConnection = false }
            do {
                _ = try await connectionPlanner.checkConnection()
                connectionStatus = "Connected. \(connectionPlanner.model.title) is available. This checks model access; generating plans uses your API billing and quota."
            } catch is CancellationError {
                connectionStatus = "Connection test cancelled."
            } catch { connectionStatus = error.localizedDescription }
        }
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isOnboardingPresented = false
    }

    func cancelPendingWork() {
        scanTask?.cancel()
        planningTask?.cancel()
        simulationTask?.cancel()
    }

    private func refreshAPIKeyStatus() {
        do {
            let key = try apiKeyManager.retrieve()
            hasAPIKey = key != nil
            maskedAPIKey = key.map { "sk-••••••••••••" + $0.suffix(4) } ?? "Not connected"
        } catch {
            hasAPIKey = false
            connectionStatus = error.localizedDescription
        }
    }

    private func restoreExactAccess(to root: URL) throws {
        let resolved = try folderAccessStore.restoreAccess(to: root)
        guard resolved.standardizedFileURL == root.standardizedFileURL else {
            throw SafeRunError.planNotExecutable("The selected folder moved. Choose its new location and create a new plan. Existing recovery paths must be inspected before restoring.")
        }
    }

    private func updateScanProgress(_ count: Int) { scannedEntries = count }
    private func updateSimulationProgress(_ count: Int, total: Int) {
        simulationProgress = total == 0 ? 1 : Double(count) / Double(total)
    }

    private func refreshRecovery() async {
        do {
            let durableJournals = try executionEngine.completedJournals()
            for journal in durableJournals { try await rollbackStore.append(journal) }
            rollbackJournals = try await rollbackStore.loadVerified()
            interruptedTransactions = try executionEngine.discoverInterruptedTransactions()
            for journal in durableJournals where !historyItems.contains(where: { $0.id == journal.planID }) {
                let restored = RunHistoryItem(id: journal.planID, timestamp: journal.createdAt,
                    instruction: "Recovered completed run", selectedDirectory: journal.rootFolder,
                    operationCount: journal.entries.count, risk: .high,
                    result: "Completed — recovered from transaction journal", rollbackAvailable: true)
                try await historyStore.update(restored)
            }
            historyItems = await historyStore.load()
            refreshRecoveryUsage()
        } catch { errorMessage = "Recovery records could not be loaded. Keep SafeRun's recovery storage intact. \(error.localizedDescription)" }
    }

    func recoverInterruptedRun(_ transaction: ExecutionTransaction) {
        guard !isBusy else { return }
        isRollingBack = true
        Task {
            defer { isRollingBack = false }
            do {
                try restoreExactAccess(to: transaction.journal.rootFolder)
                try await executionEngine.recover(transaction.id)
                try await rollbackStore.remove(transaction.journal.id)
                try await updateHistory(planID: transaction.journal.planID, result: "Interrupted run recovered", rollbackAvailable: false)
            } catch { errorMessage = "Recovery needs attention. \(error.localizedDescription)" }
            await refreshRecovery()
        }
    }

    func refreshRecoveryUsage() {
        Task { recoveryBytes = await RecoveryStorage.byteCount() }
    }

    func openRecoveryFolder() {
        do {
            let root = TransactionStore.defaultRecoveryDirectory
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            NSWorkspace.shared.open(root)
        } catch { errorMessage = "SafeRun could not open recovery storage. \(error.localizedDescription)" }
    }

    func clearExpiredRecoveryData() {
        guard !isBusy else { return }
        isRollingBack = true
        Task {
            defer { isRollingBack = false }
            let storedDays = UserDefaults.standard.integer(forKey: "recoveryRetentionDays")
            let days = min(max(storedDays == 0 ? 30 : storedDays, 1), 365)
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            do {
                let removed = try executionEngine.cleanupCompletedTransactions(olderThan: cutoff)
                for journal in rollbackJournals where removed.contains(journal.id) {
                    try await rollbackStore.remove(journal.id)
                    try await updateHistory(planID: journal.planID, result: "Recovery expired", rollbackAvailable: false)
                }
                await refreshRecovery()
            } catch { errorMessage = "Expired recovery data could not be cleared. \(error.localizedDescription)" }
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
