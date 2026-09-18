import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Group {
                switch viewModel.selectedSection {
                case .dashboard: DashboardView()
                case .simulations: SimulationsView()
                case .completedRuns: CompletedRunsView()
                case .rollbacks: RollbacksView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 270)
        .alert("SafeRun", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(SafeRunPalette.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SafeRun")
                        .font(.headline.weight(.bold))
                    Text("Preview first. Run safely.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 18)
            .padding(.bottom, 14)

            List(selection: $viewModel.selectedSection) {
                Section("Workspace") {
                    ForEach([AppSection.dashboard, .simulations]) { section in
                        sidebarRow(section)
                    }
                }

                Section("History") {
                    ForEach([AppSection.completedRuns, .rollbacks]) { section in
                        sidebarRow(section)
                    }
                }

                Section {
                    sidebarRow(.settings)
                }
            }
            .listStyle(.sidebar)
        }
        .background(.regularMaterial)
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
            .padding(.vertical, 3)
    }
}
