import SwiftUI

/// Shared by Settings and onboarding. Credentials live only in transient field state.
struct AIConnectionView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @AppStorage("plannerModel") private var plannerModel = PlannerModel.terra.rawValue
    @State private var apiKey = ""
    @State private var isChangingKey = false
    @State private var isRemoveConfirmationPresented = false

    private var isEditing: Bool { !viewModel.hasAPIKey || isChangingKey }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("OpenAI", systemImage: "sparkles").font(.headline)
                Spacer()
                GlassStatusPill(
                    title: viewModel.hasAPIKey ? "Key saved" : "Not configured",
                    systemImage: viewModel.hasAPIKey ? "key.fill" : "key",
                    tint: viewModel.hasAPIKey ? SafeRunTheme.safe : SafeRunTheme.caution
                )
            }
            if viewModel.hasAPIKey {
                LabeledContent("Saved API key", value: viewModel.maskedAPIKey)
                    .font(.callout.monospaced())
                    .privacySensitive()
            }
            if isEditing {
                SecureField(viewModel.hasAPIKey ? "New OpenAI API key" : "OpenAI API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()
                    .onSubmit(saveKey)
                    .disabled(viewModel.isTestingConnection)
                HStack {
                    GlassButton(
                        prominence: .prominent,
                        isDisabled: trimmedKey.isEmpty || viewModel.isTestingConnection,
                        action: saveKey
                    ) {
                        Label(viewModel.hasAPIKey ? "Replace Key" : "Save Key", systemImage: "lock")
                    }
                    if viewModel.hasAPIKey {
                        Button("Cancel") {
                            apiKey = ""
                            isChangingKey = false
                        }
                    }
                }
            } else {
                HStack {
                    Button("Change API Key") { isChangingKey = true }
                    Button("Remove API Key…", role: .destructive) {
                        isRemoveConfirmationPresented = true
                    }
                }
                .disabled(viewModel.isTestingConnection)
            }
            Picker("Planner model", selection: $plannerModel) {
                ForEach([PlannerModel.luna, .terra, .sol], id: \.rawValue) { model in
                    Text(model.title).tag(model.rawValue)
                }
            }
            .disabled(viewModel.isTestingConnection)
            HStack(spacing: 10) {
                GlassButton(
                    isDisabled: !viewModel.hasAPIKey || viewModel.isTestingConnection || isChangingKey,
                    action: { viewModel.testAIConnection() }
                ) {
                    Label("Test Connection", systemImage: "network")
                }
                if viewModel.isTestingConnection {
                    ProgressView().controlSize(.small)
                    Text("Testing…").foregroundStyle(.secondary)
                }
            }
            if !viewModel.connectionStatus.isEmpty {
                Text(viewModel.connectionStatus)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Connection status: \(viewModel.connectionStatus)")
            }
            Text("Use your own OpenAI API key. SafeRun does not include a shared key. Credentials are saved in macOS Keychain; requests use your OpenAI account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear { apiKey = "" }
        .confirmationDialog("Remove your API key?", isPresented: $isRemoveConfirmationPresented, titleVisibility: .visible) {
            Button("Remove API Key", role: .destructive) {
                viewModel.removeAPIKey()
                apiKey = ""
                isChangingKey = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("New AI plans will be unavailable until you add a key. Your history and recovery data will remain accessible.")
        }
    }

    private func saveKey() {
        guard !trimmedKey.isEmpty, !viewModel.isTestingConnection else { return }
        viewModel.saveAPIKey(trimmedKey)
        apiKey = ""
        isChangingKey = false
    }
}
