import SwiftUI

struct CompletedRunsView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.historyItems) { item in
                            HistoryCard(item: item) {
                                viewModel.openSimulation(item)
                            }
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

                FloatingGlassPanel(padding: 26, tint: SafeRunTheme.safe.opacity(0.14)) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(SafeRunTheme.safe)
                                .frame(width: 66, height: 66)
                                .background(SafeRunTheme.safe.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Rollback center is ready")
                                    .font(.title3.weight(.bold))
                                Text("No recovery journals exist yet. SafeRun will preserve deleted and replaced files before execution in a future execution milestone.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 12) {
                            GlassStatusPill(
                                title: "Nothing is permanently deleted",
                                systemImage: "lock.shield",
                                tint: SafeRunTheme.safe
                            )
                            Spacer()
                            GlassButton(action: { viewModel.selectedSection = .dashboard }) {
                                Label("Back to Dashboard", systemImage: "arrow.left")
                            }
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
