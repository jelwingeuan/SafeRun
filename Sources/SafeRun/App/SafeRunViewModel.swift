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
    @Published var errorMessage: String?

    private let scanner = FolderContextScanner()
    private let planner = MockAutomationPlanner()
    private let simulationEngine = SimulationEngine()
    private let executionEngine = SafeExecutionEngine()
    private let historyStore = RunHistoryStore()
    private var folderAccessURL: URL?
    private var scanTask: Task<Void, Never>?

    init() {
        Task { [weak self] in
            guard let self else { return }
            historyItems = await historyStore.load()
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
        let normalizedURL = PathValidator.normalized(url)
        folderAccessURL?.stopAccessingSecurityScopedResource()
        folderAccessURL = normalizedURL
        _ = normalizedURL.startAccessingSecurityScopedResource()
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

    func openSimulation(_ item: RunHistoryItem) {
        acceptFolder(item.selectedDirectory)
        instruction = item.instruction
        selectedSection = .dashboard
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

    func approveCurrentPlanForExecution() {
        guard var plan, let simulationResult else { return }

        do {
            try executionEngine.validateApproval(plan: plan, simulation: simulationResult, userApproved: true)
            plan.status = .approved
            self.plan = plan
            errorMessage = "This plan has passed SafeRun’s current approval gate. File execution remains disabled in this preview milestone, so no source files were changed."
        } catch {
            errorMessage = error.localizedDescription
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
            rollbackAvailable: result.canExecute
        )
        do {
            try await historyStore.append(item)
            historyItems = await historyStore.load()
        } catch {
            errorMessage = "The plan was created, but SafeRun could not save it to local history."
        }
    }
}
