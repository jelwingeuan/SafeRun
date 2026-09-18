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
                        SafeRunCard {
                            EmptyStateView(
                                systemImage: "waveform.path.ecg",
                                title: "No simulations yet",
                                message: "Start from the Dashboard to select a folder and describe the automation you want to preview.",
                                actionTitle: "Go to Dashboard",
                                action: { viewModel.selectedSection = .dashboard }
                            )
                        }
                    } else {
                        LazyVStack(spacing: 12) {
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
                .padding(30)
                .frame(maxWidth: 1_020, alignment: .leading)
            }
        }
    }
}

struct PlanPreviewView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    let plan: SafeRunPlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            viewModel.plan = nil
                            viewModel.simulationResult = nil
                        } label: {
                            Label("All simulations", systemImage: "chevron.left")
                        }
                        .buttonStyle(.link)
                        Text("SafeRun Preview")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(plan.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    RiskBadge(risk: viewModel.simulationResult?.overallRisk ?? plan.overallRisk)
                }

                Text("\(plan.totalOperations) operations detected")
                    .font(.title3.weight(.semibold))

                summaryGrid

                if !plan.warnings.isEmpty {
                    noticeCard(title: "Review notes", icon: "info.circle", color: SafeRunPalette.warm, messages: plan.warnings)
                }
                if !plan.conflicts.isEmpty {
                    noticeCard(title: "Conflicts need attention", icon: "exclamationmark.triangle.fill", color: .red, messages: plan.conflicts)
                }

                HStack(alignment: .top, spacing: 18) {
                    SafeRunCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Text("Proposed operations")
                                    .font(.headline)
                                Spacer()
                                Text("Select an operation for details")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if plan.actions.isEmpty {
                                Text("No filesystem changes were proposed for this folder.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(plan.actions) { action in
                                    Button {
                                        viewModel.selectedActionID = action.id
                                    } label: {
                                        OperationRow(action: action, isSelected: viewModel.selectedActionID == action.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let selectedAction = viewModel.selectedAction {
                        ActionDetailCard(action: selectedAction)
                            .frame(width: 285)
                    }
                }

                SimulationPanel(plan: plan)
            }
            .padding(30)
            .frame(maxWidth: 1_180, alignment: .leading)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12)], spacing: 12) {
            SummaryMetricCard(title: "Create", value: count(.createDirectory), systemImage: "folder.badge.plus")
            SummaryMetricCard(title: "Move", value: count(.moveFile), systemImage: "arrow.right")
            SummaryMetricCard(title: "Rename", value: count(.renameFile), systemImage: "pencil")
            SummaryMetricCard(title: "Delete", value: count(.deleteFile), systemImage: "trash", tint: .orange)
            SummaryMetricCard(title: "Overwrite", value: count(.replaceFile), systemImage: "arrow.triangle.2.circlepath", tint: .red)
            SummaryMetricCard(title: "Affected files", value: "\(plan.affectedFileCount)", systemImage: "doc.on.doc")
        }
    }

    private func count(_ type: SafeRunActionType) -> String {
        "\(plan.actions.filter { $0.type == type }.count)"
    }

    private func noticeCard(title: String, icon: String, color: Color, messages: [String]) -> some View {
        SafeRunCard(padding: 16) {
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

struct ActionDetailCard: View {
    let action: SafeRunAction

    var body: some View {
        SafeRunCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Action details")
                        .font(.headline)
                    Spacer()
                    Image(systemName: action.type.systemImage)
                        .foregroundStyle(SafeRunPalette.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(action.type.description)
                        .font(.title3.weight(.semibold))
                    Text(action.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Divider()
                detailRow("Risk", RiskBadge(risk: action.risk))
                detailRow("Reversible", Text(action.isReversible ? "Yes" : "Needs recovery copy"))
                if let source = action.sourceURL {
                    detailRow("From", Text(source.lastPathComponent).lineLimit(1))
                }
                if let destination = action.destinationURL {
                    detailRow("To", Text(destination.lastPathComponent).lineLimit(1))
                }
            }
        }
    }

    private func detailRow<Content: View>(_ title: String, _ content: Content) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content
                .font(.caption.weight(.medium))
        }
    }
}

struct SimulationPanel: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    let plan: SafeRunPlan

    var body: some View {
        SafeRunCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.simulationResult == nil ? "Ready to simulate" : "Simulation complete")
                            .font(.headline)
                        Text(viewModel.simulationResult == nil ? "SafeRun will test destinations, conflicts, and rollback readiness without modifying the real folder." : "No source files were modified while creating this preview.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: viewModel.simulationResult == nil ? "hourglass" : "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.simulationResult == nil ? SafeRunPalette.warm : SafeRunPalette.mint)
                }

                if let result = viewModel.simulationResult {
                    HStack(spacing: 26) {
                        simulationStat("Passed checks", value: "\(result.actionsPassed)", icon: "checkmark.circle", color: SafeRunPalette.mint)
                        simulationStat("Conflicts", value: "\(result.conflicts.count)", icon: "exclamationmark.triangle", color: result.conflicts.isEmpty ? .secondary : .red)
                        simulationStat("Warnings", value: "\(result.warnings.count)", icon: "info.circle", color: SafeRunPalette.warm)
                        Spacer()
                    }
                    if !result.conflicts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Conflicts")
                                .font(.subheadline.weight(.semibold))
                            ForEach(result.conflicts, id: \.self) { conflict in
                                Label(conflict, systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(12)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                } else if viewModel.isSimulating {
                    VStack(alignment: .leading, spacing: 9) {
                        ProgressView(value: 0.65)
                            .tint(SafeRunPalette.accent)
                        Text("Testing destinations and validating rollback…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if viewModel.simulationResult != nil {
                        Label("No source files modified", systemImage: "lock.shield")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SafeRunPalette.mint)
                    }
                    Spacer()
                    Button {
                        viewModel.simulate()
                    } label: {
                        if viewModel.isSimulating {
                            ProgressView().controlSize(.small)
                            Text("Simulating…")
                        } else {
                            Label(viewModel.simulationResult == nil ? "Simulate" : "Simulate Again", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isSimulating || plan.actions.isEmpty)
                }
            }
        }
    }

    private func simulationStat(_ title: String, value: String, icon: String, color: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
        }
    }
}

struct HistoryListRow: View {
    let item: RunHistoryItem

    var body: some View {
        SafeRunCard(padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(SafeRunPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(SafeRunPalette.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.selectedDirectory.lastPathComponent)
                        .font(.body.weight(.semibold))
                    Text(item.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(item.operationCount) operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RiskBadge(risk: item.risk)
            }
        }
    }
}
