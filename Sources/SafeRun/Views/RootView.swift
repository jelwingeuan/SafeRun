import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        ZStack {
            SafeRunAtmosphere()

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
                .background(.clear)
            }
            .navigationSplitViewStyle(.balanced)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlassToolbar {
                    Label("SafeRun", systemImage: "checkmark.shield.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(SafeRunTheme.accent)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.selectedAction != nil {
                    Button {
                        viewModel.isActionInspectorPresented.toggle()
                    } label: {
                        Label("Action Inspector", systemImage: "sidebar.right")
                    }
                    .help("Show action inspector")
                }

                Button {
                    viewModel.chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                }
                .help("Choose a folder to preview")
            }
        }
        .inspector(isPresented: $viewModel.isActionInspectorPresented) {
            if let action = viewModel.selectedAction {
                ActionInspectorView(action: action)
                    .inspectorColumnWidth(min: 280, ideal: 330, max: 420)
            } else {
                ContentUnavailableView(
                    "No action selected",
                    systemImage: "cursorarrow.click.2",
                    description: Text("Select a proposed operation to inspect its safety details.")
                )
                .inspectorColumnWidth(min: 280, ideal: 330, max: 420)
            }
        }
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
    @Namespace private var sidebarNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(SafeRunTheme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SafeRun")
                        .font(.headline.weight(.bold))
                    Text("Preview first. Run safely.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 22)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sidebarGroup("WORKSPACE", sections: [.dashboard, .simulations])
                    sidebarGroup("HISTORY", sections: [.completedRuns, .rollbacks])
                    sidebarGroup("PREFERENCES", sections: [.settings])
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
            }

            Spacer(minLength: 0)

            if let folder = viewModel.selectedFolder {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(SafeRunTheme.accent)
                    Text(folder.lastPathComponent)
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
            }
        }
    }

    private func sidebarGroup(_ title: String, sections: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 11)
                .padding(.bottom, 3)

            ForEach(sections) { section in
                SidebarNavigationItem(
                    section: section,
                    isSelected: viewModel.selectedSection == section,
                    namespace: sidebarNamespace
                ) {
                    viewModel.selectedSection = section
                }
            }
        }
    }
}

private struct SidebarNavigationItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let section: AppSection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSelected {
                    rowLabel
                        .safeRunGlassSurface(
                            tint: SafeRunTheme.accent.opacity(0.28),
                            cornerRadius: 12,
                            interactive: true
                        )
                        .safeRunGlassEffectID("sidebar-selection", in: namespace)
                } else {
                    rowLabel
                        .background(isHovering ? Color.primary.opacity(0.055) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : SafeRunMotion.quick, value: isSelected)
        .animation(reduceMotion ? nil : SafeRunMotion.quick, value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowLabel: some View {
        Label(section.title, systemImage: section.systemImage)
            .font(.body.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
    }
}

struct ActionInspectorView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    let action: SafeRunAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: action.type.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SafeRunTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Action Inspector")
                            .font(.headline)
                        Text(action.type.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                GlassCard(padding: 16, tint: action.risk.tint.opacity(0.14)) {
                    VStack(alignment: .leading, spacing: 15) {
                        inspectorValue("Action", value: action.description)
                        inspectorValue("Reason", value: action.description)
                        if let source = action.sourceURL {
                            inspectorValue("Source", value: source.path, selectable: true)
                        }
                        if let destination = action.destinationURL {
                            inspectorValue("Destination", value: destination.path, selectable: true)
                        }
                        HStack(alignment: .top) {
                            Text("Risk")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 84, alignment: .leading)
                            RiskBadge(risk: action.risk)
                        }
                        inspectorValue("Reversible", value: action.isReversible ? "Yes — recovery is planned" : "Recovery copy required")
                        inspectorValue("Simulation", value: simulationStatus)
                    }
                }

                Text("Every operation remains inside the selected folder and is reviewed before any future execution step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .navigationTitle("Action Inspector")
    }

    private var simulationStatus: String {
        switch action.validationStatus {
        case .pending: "Waiting for simulation"
        case .passed: "Passed simulated safety checks"
        case .failed: "Needs attention before approval"
        }
    }

    private func inspectorValue(_ title: String, value: String, selectable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            if selectable {
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
