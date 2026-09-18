import SwiftUI

struct SimulationsView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        if let plan = viewModel.plan {
            PlanPreviewView(plan: plan)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                        VStack(spacing: 12) {
                            ForEach(viewModel.historyItems) { item in
                                Button {
                                    viewModel.openSimulation(item)
                                } label: {
                                    HistoryListRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 34)
                .frame(maxWidth: SafeRunTheme.pageWidth, alignment: .leading)
            }
        }
    }
}

struct PlanPreviewView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @Namespace private var simulationNamespace

    let plan: SafeRunPlan

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    previewHeader
                    GlassEffectGroup {
                        SimulationStatusSurface(plan: plan, namespace: simulationNamespace)
                    }
                    summaryGrid

                    if !plan.warnings.isEmpty {
                        noticeCard(
                            title: "Review notes",
                            icon: "info.circle",
                            color: SafeRunTheme.caution,
                            messages: plan.warnings
                        )
                    }

                    if !plan.conflicts.isEmpty {
                        noticeCard(
                            title: "Conflicts need attention",
                            icon: "exclamationmark.triangle.fill",
                            color: SafeRunTheme.danger,
                            messages: plan.conflicts
                        )
                    }

                    operationsCard

                    if let result = viewModel.simulationResult {
                        FilesystemComparisonView(plan: plan, result: result)
                    }

                    if plan.status == .approved {
                        GlassCard(padding: 16, tint: SafeRunTheme.safe.opacity(0.18)) {
                            Label(
                                "Plan approved for a future execution engine. No source files have been modified.",
                                systemImage: "lock.shield"
                            )
                            .font(.callout.weight(.medium))
                            .foregroundStyle(SafeRunTheme.safe)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 34)
                .padding(.bottom, 118)
                .frame(maxWidth: 1_220, alignment: .leading)
            }

            GlassActionBar(
                actionCount: plan.totalOperations,
                risk: viewModel.simulationResult?.overallRisk ?? plan.overallRisk,
                simulationResult: viewModel.simulationResult,
                isSimulating: viewModel.isSimulating,
                isApproved: plan.status == .approved,
                onCancel: viewModel.cancelCurrentPlan,
                onEditPlan: viewModel.editCurrentPlan,
                onPrimaryAction: {
                    if viewModel.simulationResult == nil {
                        viewModel.simulate()
                    } else {
                        viewModel.approveCurrentPlanForExecution()
                    }
                }
            )
            .padding(.horizontal, 34)
            .padding(.bottom, 22)
            .frame(maxWidth: 1_180)
        }
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                GlassButton(action: viewModel.cancelCurrentPlan) {
                    Label("All simulations", systemImage: "chevron.left")
                }
                Text("Simulation")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(plan.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RiskBadge(risk: viewModel.simulationResult?.overallRisk ?? plan.overallRisk)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 12)], spacing: 12) {
            SummaryMetricCard(title: "Create", value: count(.createDirectory), systemImage: "folder.badge.plus")
            SummaryMetricCard(title: "Move", value: count(.moveFile), systemImage: "arrow.right")
            SummaryMetricCard(title: "Rename", value: count(.renameFile), systemImage: "pencil")
            SummaryMetricCard(title: "Delete", value: count(.deleteFile), systemImage: "trash", tint: SafeRunTheme.caution)
            SummaryMetricCard(title: "Overwrite", value: count(.replaceFile), systemImage: "arrow.triangle.2.circlepath", tint: SafeRunTheme.danger)
            SummaryMetricCard(title: "Affected files", value: "\(plan.affectedFileCount)", systemImage: "doc.on.doc")
        }
    }

    private var operationsCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Proposed operations")
                            .font(.headline)
                        Text("Select an operation to open the Action Inspector.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassStatusPill(
                        title: "\(plan.totalOperations) total",
                        systemImage: "list.bullet",
                        tint: SafeRunTheme.accent
                    )
                }

                if plan.actions.isEmpty {
                    Text("No filesystem changes were proposed for this folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(plan.actions) { action in
                        Button {
                            viewModel.selectAction(action)
                        } label: {
                            OperationRow(action: action, isSelected: viewModel.selectedActionID == action.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func count(_ type: SafeRunActionType) -> String {
        "\(plan.actions.filter { $0.type == type }.count)"
    }

    private func noticeCard(title: String, icon: String, color: Color, messages: [String]) -> some View {
        GlassCard(padding: 16, tint: color.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
                ForEach(messages, id: \.self) { message in
                    Text("• \(message)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SimulationStatusSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var viewModel: SafeRunViewModel

    let plan: SafeRunPlan
    let namespace: Namespace.ID

    private var result: SimulationResult? { viewModel.simulationResult }

    private var title: String {
        if viewModel.isSimulating { return "SIMULATING" }
        if let result {
            return result.canExecute ? "SIMULATION COMPLETE" : "SIMULATION NEEDS REVIEW"
        }
        return "READY TO SIMULATE"
    }

    private var subtitle: String {
        if viewModel.isSimulating { return "Testing destinations, conflicts, and rollback readiness in a protected environment." }
        if let result {
            return result.canExecute
                ? "Every current safety check passed without modifying a real file."
                : "Review the flagged conflicts before this plan can be approved."
        }
        return "No real files are being modified. SafeRun will inspect a virtual result first."
    }

    private var icon: String {
        if viewModel.isSimulating { return "shield.lefthalf.filled" }
        if let result { return result.canExecute ? "checkmark.shield.fill" : "exclamationmark.shield.fill" }
        return "lock.shield"
    }

    private var tint: Color {
        if viewModel.isSimulating { return SafeRunTheme.accent }
        if let result { return result.canExecute ? SafeRunTheme.safe : SafeRunTheme.caution }
        return SafeRunTheme.accent
    }

    var body: some View {
        FloatingGlassPanel(padding: 24, tint: tint.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.12))
                            .frame(width: 66, height: 66)
                        Image(systemName: icon)
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.caption.weight(.bold))
                            .tracking(1.25)
                            .foregroundStyle(tint)
                        Text(subtitle)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }

                if viewModel.isSimulating {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(tint)
                        Text("Checking \(plan.totalOperations) operations…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let result {
                    HStack(spacing: 26) {
                        simulationMetric("Passed", value: "\(result.actionsPassed)", symbol: "checkmark.circle.fill", tint: SafeRunTheme.safe)
                        simulationMetric("Warnings", value: "\(result.warnings.count)", symbol: "info.circle.fill", tint: SafeRunTheme.caution)
                        simulationMetric("Conflicts", value: "\(result.conflicts.count)", symbol: "exclamationmark.triangle.fill", tint: result.conflicts.isEmpty ? .secondary : SafeRunTheme.danger)
                        simulationMetric("Reversible", value: reversibilityText, symbol: "arrow.uturn.backward.circle.fill", tint: SafeRunTheme.accent)
                        Spacer(minLength: 0)
                    }
                } else {
                    Label("Simulation stays isolated from your selected folder.", systemImage: "lock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeRunGlassEffectID("simulation-status", in: namespace)
        .safeRunGlassTransition()
        .animation(reduceMotion ? nil : SafeRunMotion.gentle, value: title)
    }

    private var reversibilityText: String {
        guard plan.totalOperations > 0 else { return "—" }
        return plan.reversibleActionCount == plan.totalOperations
            ? "100%"
            : "\(plan.reversibleActionCount) / \(plan.totalOperations)"
    }

    private func simulationMetric(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
        }
    }
}

private enum FilesystemComparisonMode: String, CaseIterable, Identifiable {
    case sideBySide = "Before / After"
    case changesOnly = "Changes Only"

    var id: String { rawValue }
}

private struct FilesystemComparisonView: View {
    @State private var mode: FilesystemComparisonMode = .sideBySide

    let plan: SafeRunPlan
    let result: SimulationResult

    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Filesystem comparison")
                            .font(.headline)
                        Text("A virtual before-and-after view of \(result.actionsPassed) validated changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Comparison mode", selection: $mode) {
                        ForEach(FilesystemComparisonMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                if mode == .sideBySide {
                    sideBySide
                } else {
                    changesOnly
                }
            }
        }
    }

    private var sideBySide: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BEFORE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("AFTER")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.9)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 7)

            ForEach(plan.actions) { action in
                HStack(spacing: 12) {
                    comparisonFileLabel(beforeName(for: action), isMuted: action.type == .createDirectory)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    comparisonIndicator(for: action)
                        .frame(width: 30)
                    comparisonFileLabel(afterName(for: action), isMuted: action.type == .deleteFile)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var changesOnly: some View {
        VStack(spacing: 8) {
            ForEach(plan.actions) { action in
                HStack(spacing: 12) {
                    comparisonIndicator(for: action)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.description)
                            .font(.callout.weight(.medium))
                        Text(changePath(for: action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    RiskBadge(risk: action.risk)
                }
                .padding(12)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func comparisonFileLabel(_ title: String, isMuted: Bool) -> some View {
        Label(title, systemImage: "doc")
            .font(.caption.weight(.medium))
            .foregroundStyle(isMuted ? .tertiary : .secondary)
            .lineLimit(1)
    }

    private func comparisonIndicator(for action: SafeRunAction) -> some View {
        Image(systemName: changeSymbol(for: action.type))
            .font(.caption.weight(.bold))
            .foregroundStyle(changeTint(for: action.type))
            .frame(width: 26, height: 26)
            .background(changeTint(for: action.type).opacity(0.10), in: Circle())
            .accessibilityLabel("\(action.type.title) change")
    }

    private func beforeName(for action: SafeRunAction) -> String {
        if action.type == .createDirectory { return "New folder" }
        return action.sourceURL?.lastPathComponent ?? action.filename
    }

    private func afterName(for action: SafeRunAction) -> String {
        if action.type == .deleteFile { return "Removed" }
        return action.destinationURL?.lastPathComponent ?? action.filename
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

struct HistoryListRow: View {
    let item: RunHistoryItem

    var body: some View {
        InteractiveGlassCard(padding: 16, tint: item.risk.tint.opacity(0.12)) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(SafeRunTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.selectedDirectory.lastPathComponent)
                        .font(.body.weight(.semibold))
                    Text(item.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(item.operationCount) operations")
                    Text(item.timestamp, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                RiskBadge(risk: item.risk)
            }
        }
    }
}
