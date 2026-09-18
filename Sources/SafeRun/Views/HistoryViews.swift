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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                pageHeader(
                    eyebrow: "RECOVERY",
                    title: "Rollbacks",
                    subtitle: "Recovery journals stay local and keep every approved change understandable.",
                    systemImage: "arrow.uturn.backward.circle"
                )

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
                                    Text("\(journal.entries.count) recovery entries · \(journal.createdAt, style: .relative)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: SafeRunSpacing.small)

                                GlassButton(
                                    tint: SafeRunTheme.caution,
                                    isDisabled: viewModel.isRollingBack,
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
        .confirmationDialog(
            "Roll back this run?",
            item: $journalToRollback,
            titleVisibility: .visible
        ) { journal in
            Button("Roll Back Changes", role: .destructive) {
                viewModel.rollback(journal)
            }
            Button("Cancel", role: .cancel) {}
        } message: { journal in
            Text("SafeRun will restore the saved recovery entries inside \(journal.rootFolder.lastPathComponent).")
        }
    }
}
