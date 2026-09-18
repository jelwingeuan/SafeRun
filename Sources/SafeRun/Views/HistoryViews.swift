import SwiftUI

struct CompletedRunsView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                pageHeader(
                    eyebrow: "LOCAL HISTORY",
                    title: "Completed Runs",
                    subtitle: "A clear record of every SafeRun preview and its recovery readiness.",
                    systemImage: "checkmark.circle"
                )

                if viewModel.historyItems.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            systemImage: "checkmark.circle",
                            title: "No completed runs",
                            message: "After a SafeRun plan completes, its summary and rollback status will be saved here locally.",
                            actionTitle: "Create a Simulation",
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

struct RollbacksView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @State private var journalToRollback: RollbackJournal?
    @State private var transactionToRecover: ExecutionTransaction?

    private var recoveryDialogIsPresented: Binding<Bool> {
        Binding(
            get: { transactionToRecover != nil },
            set: { if !$0 { transactionToRecover = nil } }
        )
    }

    private var rollbackDialogIsPresented: Binding<Bool> {
        Binding(
            get: { journalToRollback != nil },
            set: { if !$0 { journalToRollback = nil } }
        )
    }

    private var rollbackFolderName: String {
        journalToRollback?.rootFolder.lastPathComponent ?? "the selected folder"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                pageHeader(
                    eyebrow: "RECOVERY",
                    title: "Rollbacks",
                    subtitle: "Recovery journals stay local and keep every approved change understandable.",
                    systemImage: "arrow.uturn.backward.circle"
                )

                ForEach(viewModel.interruptedTransactions) { transaction in
                    GlassCard(tint: SafeRunTheme.caution.opacity(0.12)) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SafeRun detected an interrupted run.").font(.headline)
                            Text(transaction.journal.rootFolder.path).font(.caption).textSelection(.enabled)
                            if let failure = transaction.failure { Text(failure).font(.callout) }
                            ForEach(transaction.entries, id: \.action.id) { entry in
                                RecoveryEntrySummary(entry: entry)
                            }
                            Button("Attempt Recovery") { transactionToRecover = transaction }
                                .disabled(viewModel.isBusy)
                            Text("If access was revoked, choose this folder again before attempting recovery.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if viewModel.rollbackJournals.isEmpty {
                    GlassCard(padding: SafeRunSpacing.large, tint: SafeRunTheme.safe.opacity(0.10)) {
                        HStack(alignment: .top, spacing: SafeRunSpacing.medium) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(SafeRunTheme.safe)
                                .frame(width: 42, height: 42)
                                .background(SafeRunTheme.safe.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: SafeRunSpacing.small) {
                                Text("No rollback journals yet")
                                    .font(.headline)
                                Text("When SafeRun changes files, deleted and replaced items will be preserved here for recovery.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.rollbackJournals) { journal in
                            HStack(spacing: SafeRunSpacing.medium) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundStyle(SafeRunTheme.safe)
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(journal.rootFolder.lastPathComponent)
                                        .font(.callout.weight(.semibold))
                                    HStack(spacing: 4) {
                                        Text("\(journal.entries.count) recovery entries")
                                        Text(journal.createdAt, style: .relative)
                                    }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: SafeRunSpacing.small)

                                GlassButton(
                                    tint: SafeRunTheme.caution,
                                    isDisabled: viewModel.isBusy,
                                    action: { journalToRollback = journal }
                                ) {
                                    Label("Roll Back", systemImage: "arrow.uturn.backward")
                                }
                            }
                            .padding(.horizontal, SafeRunSpacing.medium)
                            .padding(.vertical, SafeRunSpacing.medium)
                            if journal.id != viewModel.rollbackJournals.last?.id {
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
        .confirmationDialog("Attempt recovery?", isPresented: recoveryDialogIsPresented, titleVisibility: .visible) {
            Button("Attempt Recovery", role: .destructive) {
                guard let transaction = transactionToRecover else { return }
                transactionToRecover = nil
                viewModel.recoverInterruptedRun(transaction)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("SafeRun will inspect the durable journal and undo changes it can verify. Changed or ambiguous items will be reported for manual inspection.")
        }
        .confirmationDialog(
            "Roll back this run?",
            isPresented: rollbackDialogIsPresented,
            titleVisibility: .visible
        ) {
            Button("Roll Back Changes", role: .destructive) {
                guard let journal = journalToRollback else { return }
                journalToRollback = nil
                viewModel.rollback(journal)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SafeRun will restore the saved recovery entries inside \(rollbackFolderName).")
        }
    }
}

private struct RecoveryEntrySummary: View {
    let entry: ExecutionTransaction.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.action.description)
            Text(entry.phase.rawValue)
                .foregroundStyle(.secondary)
            if let failure = entry.failure {
                Text(failure)
                    .foregroundStyle(SafeRunTheme.danger)
            }
        }
        .font(.caption)
        .textSelection(.enabled)
    }
}
