import SwiftUI

struct CompletedRunsView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    eyebrow: "LOCAL HISTORY",
                    title: "Completed Runs",
                    subtitle: "A clear record of what SafeRun has previewed or completed.",
                    systemImage: "checkmark.circle"
                )
                if viewModel.historyItems.isEmpty {
                    SafeRunCard {
                        EmptyStateView(
                            systemImage: "checkmark.circle",
                            title: "No completed runs",
                            message: "After a SafeRun plan completes, its summary and rollback status will be saved here locally.",
                            actionTitle: "Create a Simulation",
                            action: { viewModel.selectedSection = .dashboard }
                        )
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.historyItems) { item in
                            HistoryListRow(item: item)
                        }
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 1_020, alignment: .leading)
        }
    }
}

struct RollbacksView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    eyebrow: "RECOVERY",
                    title: "Rollbacks",
                    subtitle: "Recovery journals stay local and keep every approved change understandable.",
                    systemImage: "arrow.uturn.backward.circle"
                )
                SafeRunCard {
                    EmptyStateView(
                        systemImage: "lock.shield",
                        title: "Rollback center is ready",
                        message: "No recovery journals exist yet. SafeRun will preserve deleted and replaced files before execution in a future execution milestone.",
                        actionTitle: "Back to Dashboard",
                        action: { viewModel.selectedSection = .dashboard }
                    )
                }
            }
            .padding(30)
            .frame(maxWidth: 1_020, alignment: .leading)
        }
    }
}
