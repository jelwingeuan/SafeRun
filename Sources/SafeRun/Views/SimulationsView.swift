import SwiftUI

struct SimulationsView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        if let plan = viewModel.plan {
            PlanPreviewView(plan: plan)
                .id(plan.id)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                    pageHeader(
                        eyebrow: "SAFE PREVIEWS",
                        title: "Simulations",
                        subtitle: "Review every proposed change before anything runs.",
                        systemImage: "waveform.path.ecg"
                    )

                    if viewModel.historyItems.isEmpty {
                        GlassCard {
                            EmptyStateView(
                                systemImage: "waveform.path.ecg",
                                title: "No simulations yet",
                                message: "Start from the Dashboard to select a folder and describe the automation you want to preview.",
                                actionTitle: "Go to Dashboard",
                                action: { viewModel.selectedSection = .dashboard }
                            )
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(viewModel.historyItems) { item in
                                ActivityRow(item: item) {
                                    viewModel.openSimulation(item)
                                }
                                if item.id != viewModel.historyItems.last?.id {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.vertical, SafeRunSpacing.xSmall)
                        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous)
                                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, SafeRunSpacing.xLarge)
                .padding(.vertical, SafeRunSpacing.xLarge)
                .frame(maxWidth: SafeRunTheme.pageWidth, alignment: .leading)
            }
        }
    }
}

private enum WorkspaceMode: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case changes = "Changes"
    case beforeAfter = "Before & After"

    var id: String { rawValue }
}

struct PlanPreviewView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @State private var workspaceMode: WorkspaceMode = .plan
    @State private var operationFilter: OperationFilter = .all
    @State private var operationSearch = ""
    @State private var isExecutionConfirmationPresented = false

    let plan: SafeRunPlan

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                    WorkspaceHeader(
                        title: plan.title,
                        subtitle: "\(plan.totalOperations) planned operations · \(plan.selectedRootFolder.lastPathComponent)",
                        risk: viewModel.simulationResult?.overallRisk ?? plan.overallRisk,
                        statusTitle: statusTitle,
                        statusImage: statusImage,
                        statusTint: statusTint
                    )

                    OperationSummaryStrip(plan: plan, result: viewModel.simulationResult)

                    if viewModel.isExecuting {
                        executionProgress
                    }

                    if !plan.conflicts.isEmpty {
                        ConflictBanner(count: plan.conflicts.count) {
                            operationFilter = .conflicts
                            workspaceMode = .plan
                        }
                    }

                    workspacePicker

                    switch workspaceMode {
                    case .plan:
                        planWorkspace
                    case .changes:
                        changesWorkspace
                    case .beforeAfter:
                        beforeAfterWorkspace
                    }

                    if !plan.warnings.isEmpty && workspaceMode == .plan {
                        reviewNotes
                    }

                    if plan.status == .completed {
                        Label(
                            "Files were changed successfully. A rollback journal is available in Rollbacks.",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(SafeRunTheme.safe)
                        .padding(.vertical, SafeRunSpacing.small)
                    } else if plan.status == .rolledBack {
                        Label(
                            "This plan was rolled back using its recovery journal.",
                            systemImage: "arrow.uturn.backward.circle.fill"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(SafeRunTheme.accent)
                        .padding(.vertical, SafeRunSpacing.small)
                    }
                }
                .padding(.horizontal, SafeRunSpacing.xLarge)
                .padding(.top, SafeRunSpacing.xLarge)
                .padding(.bottom, 118)
                .frame(maxWidth: 1_220, alignment: .leading)
            }

            GlassActionBar(
                actionCount: plan.totalOperations,
                risk: viewModel.simulationResult?.overallRisk ?? plan.overallRisk,
                simulationResult: viewModel.simulationResult,
                isSimulating: viewModel.isSimulating,
                isExecuting: viewModel.isExecuting,
                isExecuted: plan.status == .completed || plan.status == .rolledBack,
                executionProgress: viewModel.executionProgress,
                isApproved: plan.status == .approved,
                onCancel: viewModel.cancelCurrentPlan,
                onEditPlan: viewModel.editCurrentPlan,
                onPrimaryAction: {
                    if viewModel.simulationResult == nil {
                        viewModel.simulate()
                    } else {
                        isExecutionConfirmationPresented = true
                    }
                }
            )
            .padding(.horizontal, SafeRunSpacing.xLarge)
            .padding(.bottom, SafeRunSpacing.medium)
            .frame(maxWidth: 1_180)
        }
        .confirmationDialog(
            "Run this plan on your files?",
            isPresented: $isExecutionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Run \(plan.totalOperations) Actions", role: .destructive) {
                viewModel.executeCurrentPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SafeRun will make the reviewed changes inside \(plan.selectedRootFolder.lastPathComponent). Deleted and replaced items are moved to recovery storage.")
        }
        .onChange(of: viewModel.simulationResult) { _, result in
            if result == nil {
                workspaceMode = .plan
                operationFilter = .all
                operationSearch = ""
            }
        }
    }

    private var statusTitle: String {
        if viewModel.isExecuting { return "Executing" }
        if plan.status == .completed { return "Execution complete" }
        if plan.status == .rolledBack { return "Rolled back" }
        if plan.status == .failed { return "Execution failed" }
        if viewModel.isSimulating { return "Simulating" }
        if let result = viewModel.simulationResult {
            return result.canExecute ? "Simulation complete" : "Needs review"
        }
        return "Ready to simulate"
    }

    private var statusImage: String {
        if viewModel.isExecuting { return "arrow.triangle.2.circlepath" }
        if plan.status == .completed { return "checkmark.circle.fill" }
        if plan.status == .rolledBack { return "arrow.uturn.backward.circle.fill" }
        if plan.status == .failed { return "exclamationmark.triangle.fill" }
        if viewModel.isSimulating { return "shield.lefthalf.filled" }
        if let result = viewModel.simulationResult {
            return result.canExecute ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
        }
        return "lock.shield"
    }

    private var statusTint: Color {
        if viewModel.isExecuting { return SafeRunTheme.accent }
        if plan.status == .completed { return SafeRunTheme.safe }
        if plan.status == .rolledBack { return SafeRunTheme.accent }
        if plan.status == .failed { return SafeRunTheme.danger }
        if viewModel.isSimulating { return SafeRunTheme.accent }
        if let result = viewModel.simulationResult {
            return result.canExecute ? SafeRunTheme.safe : SafeRunTheme.caution
        }
        return SafeRunTheme.accent
    }

    private var executionProgress: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.small) {
            HStack {
                Label(viewModel.executionStatus.isEmpty ? "Executing approved changes" : viewModel.executionStatus, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(viewModel.executionProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.executionProgress)
                .tint(SafeRunTheme.accent)
        }
        .padding(.horizontal, SafeRunSpacing.medium)
        .padding(.vertical, SafeRunSpacing.small)
        .background(SafeRunTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous))
    }

    private var workspacePicker: some View {
        HStack {
            Picker("Workspace view", selection: $workspaceMode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 390)
            Spacer(minLength: 0)
        }
    }

    private var planWorkspace: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Proposed operations")
                        .font(.headline)
                    Text("Select an operation to open the Action Inspector.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(filteredActions.count) shown")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            OperationFilterBar(filter: $operationFilter, searchText: $operationSearch)

            if filteredActions.isEmpty {
                emptyOperations
            } else {
                OperationTable(
                    actions: filteredActions,
                    selectedActionID: viewModel.selectedActionID,
                    onSelect: viewModel.selectAction
                )
            }
        }
    }

    private var changesWorkspace: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Changes in this plan")
                    .font(.headline)
                Text("A focused list of the filesystem changes SafeRun will validate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ChangesOnlyList(actions: filteredActions, selectedActionID: viewModel.selectedActionID, onSelect: viewModel.selectAction)
        }
    }

    private var beforeAfterWorkspace: some View {
        Group {
            if let result = viewModel.simulationResult {
                FilesystemComparisonView(plan: plan, result: result)
            } else {
                ContentUnavailableView(
                    "Run a simulation first",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("The virtual before-and-after view appears after SafeRun validates this plan.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
    }

    private var reviewNotes: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.small) {
            Label("Review notes", systemImage: "info.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(SafeRunTheme.caution)
            ForEach(plan.warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, SafeRunSpacing.small)
    }

    private var emptyOperations: some View {
        ContentUnavailableView(
            operationFilter == .all && operationSearch.isEmpty ? "No operations proposed" : "No matching operations",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text(operationFilter == .all && operationSearch.isEmpty ? "SafeRun found no filesystem changes for this instruction." : "Try a different filter or search term.")
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var filteredActions: [SafeRunAction] {
        let query = operationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return plan.actions.filter { action in
            guard operationFilter.matches(action) else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [
                action.type.title,
                action.filename,
                action.description,
                action.sourceURL?.path ?? "",
                action.destinationURL?.path ?? ""
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct ChangesOnlyList: View {
    let actions: [SafeRunAction]
    let selectedActionID: UUID?
    let onSelect: (SafeRunAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    onSelect(action)
                } label: {
                    HStack(spacing: SafeRunSpacing.medium) {
                        Image(systemName: action.type.systemImage)
                            .foregroundStyle(SafeRunTheme.accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.description)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(changePath(for: action))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: SafeRunSpacing.small)
                        RiskBadge(risk: action.risk)
                        ActionValidationLabel(status: action.validationStatus)
                    }
                    .padding(.horizontal, SafeRunSpacing.medium)
                    .padding(.vertical, SafeRunSpacing.medium)
                    .background(
                        selectedActionID == action.id ? SafeRunTheme.accent.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                if action.id != actions.last?.id {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, SafeRunSpacing.xSmall)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func changePath(for action: SafeRunAction) -> String {
        switch action.type {
        case .createDirectory:
            return action.destinationURL?.path ?? action.filename
        case .deleteFile:
            return action.sourceURL?.path ?? action.filename
        default:
            return "\(action.sourceURL?.lastPathComponent ?? action.filename) → \(action.destinationURL?.lastPathComponent ?? action.filename)"
        }
    }
}

private struct ActionValidationLabel: View {
    let status: ActionValidationStatus

    var body: some View {
        Label(status.title, systemImage: image)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
    }

    private var image: String {
        switch status {
        case .pending: "circle.dashed"
        case .passed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .pending: .secondary
        case .passed: SafeRunTheme.safe
        case .failed: SafeRunTheme.danger
        }
    }
}

private struct FilesystemComparisonView: View {
    let plan: SafeRunPlan
    let result: SimulationResult

    var body: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Virtual filesystem")
                    .font(.headline)
                Text("Before and after \(result.actionsPassed) validated changes without modifying the selected folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                HStack(spacing: SafeRunSpacing.medium) {
                    Text("BEFORE")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("")
                        .frame(width: 26)
                    Text("AFTER")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, SafeRunSpacing.medium)
                .padding(.bottom, SafeRunSpacing.small)

                ForEach(plan.actions) { action in
                    HStack(spacing: SafeRunSpacing.medium) {
                        comparisonFileLabel(beforeName(for: action), isMuted: action.type == .createDirectory)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: changeSymbol(for: action.type))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(changeTint(for: action.type))
                            .frame(width: 26, height: 26)
                            .background(changeTint(for: action.type).opacity(0.10), in: Circle())
                        comparisonFileLabel(afterName(for: action), isMuted: action.type == .deleteFile)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, SafeRunSpacing.medium)
                    .padding(.vertical, SafeRunSpacing.small)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous))
                }
            }
            .padding(.vertical, SafeRunSpacing.medium)
            .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func comparisonFileLabel(_ title: String, isMuted: Bool) -> some View {
        Label(title, systemImage: "doc")
            .font(.caption.weight(.medium))
            .foregroundStyle(isMuted ? .tertiary : .secondary)
            .lineLimit(1)
    }

    private func beforeName(for action: SafeRunAction) -> String {
        if action.type == .createDirectory { return "New folder" }
        return action.sourceURL?.lastPathComponent ?? action.filename
    }

    private func afterName(for action: SafeRunAction) -> String {
        if action.type == .deleteFile { return "Removed" }
        return action.destinationURL?.lastPathComponent ?? action.filename
    }

    private func changeSymbol(for type: SafeRunActionType) -> String {
        switch type {
        case .createDirectory: "plus"
        case .moveFile: "arrow.right"
        case .copyFile: "plus.square"
        case .renameFile: "arrow.triangle.2.circlepath"
        case .deleteFile: "minus"
        case .replaceFile: "exclamationmark"
        }
    }

    private func changeTint(for type: SafeRunActionType) -> Color {
        switch type {
        case .deleteFile, .replaceFile: SafeRunTheme.caution
        case .createDirectory: SafeRunTheme.safe
        case .moveFile, .copyFile, .renameFile: SafeRunTheme.accent
        }
    }
}
