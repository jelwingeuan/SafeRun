import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("maximumAutomaticActions") private var maximumAutomaticActions = 100
    @AppStorage("recoveryRetentionDays") private var recoveryRetentionDays = 30
    @State private var isCleanupConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                pageHeader(
                    eyebrow: "PREFERENCES",
                    title: "Settings",
                    subtitle: "Your workspace. Your choices. Safety built in.",
                    systemImage: "gearshape"
                )

                settingsSection("General", systemImage: "slider.horizontal.3") {
                    Text("Choose a folder, describe what you need, then review and simulate the plan before running it.")
                    Text("History and recovery remain available without an AI connection.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Safety", systemImage: "checkmark.shield") {
                    Toggle("Require simulation before execution", isOn: .constant(true)).disabled(true)
                    Toggle("Confirm deletes", isOn: .constant(true)).disabled(true)
                    Toggle("Confirm replacements", isOn: .constant(true)).disabled(true)
                    Text("These protections are mandatory. Every plan is validated, and operations must stay inside the folder you authorize.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Divider()
                    Stepper(value: $maximumAutomaticActions, in: 1...500) {
                        LabeledContent("Maximum actions per plan", value: maximumAutomaticActions.formatted())
                            .monospacedDigit()
                    }
                    Text("Default: 100 · Allowed range: 1–500")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection("AI", systemImage: "sparkles") {
                    AIConnectionView()
                }

                settingsSection("Recovery", systemImage: "arrow.uturn.backward.circle") {
                    LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: viewModel.recoveryBytes, countStyle: .file))
                    Stepper(value: $recoveryRetentionDays, in: 1...365) {
                        LabeledContent("Retention period", value: "\(recoveryRetentionDays) days")
                            .monospacedDigit()
                    }
                    Text("Recovery copies are stored locally. Completed runs older than this period are eligible for manual cleanup; changing the period does not delete them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        GlassButton(action: { viewModel.openRecoveryFolder() }) {
                            Label("Open Recovery Folder", systemImage: "folder")
                        }
                        Button("Clear Expired Data…", role: .destructive) {
                            isCleanupConfirmationPresented = true
                        }
                        .disabled(viewModel.isExecuting || viewModel.isRollingBack)
                    }
                }

                settingsSection("Privacy", systemImage: "hand.raised") {
                    Text("When you request a plan, SafeRun sends your instruction and selected folder metadata to OpenAI: filenames, paths, directory structure, sizes, and dates. File contents are not uploaded.")
                    Text("Names and instructions can contain private information. Choose the folder and wording you share carefully. AI proposes structured file operations; it cannot run shell commands or control your Mac.")
                        .foregroundStyle(.secondary)
                    Label("Your API key is stored in macOS Keychain.", systemImage: "lock")
                        .font(.callout)
                }

                settingsSection("Appearance", systemImage: "circle.lefthalf.filled") {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("System follows your Mac. Glass surfaces respect Reduce Transparency and Reduce Motion.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                settingsSection("About", systemImage: "info.circle") {
                    Text(SafeRunAbout.name).font(.title3.weight(.semibold))
                    Text("Know what happens before it happens.").foregroundStyle(.secondary)
                    LabeledContent("Version", value: SafeRunAbout.version)
                    LabeledContent("Build", value: SafeRunAbout.build)
                    if let copyright = SafeRunAbout.copyright {
                        Text(copyright).font(.caption).foregroundStyle(.secondary)
                    }
                    GlassButton(action: { SafeRunAbout.showPanel() }) {
                        Text("About \(SafeRunAbout.name)")
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(SafeRunSpacing.xLarge)
            .frame(maxWidth: .infinity)
        }
        .task { viewModel.refreshRecoveryUsage() }
        .onAppear {
            maximumAutomaticActions = min(max(maximumAutomaticActions, 1), 500)
            recoveryRetentionDays = min(max(recoveryRetentionDays, 1), 365)
        }
        .confirmationDialog("Clear expired recovery data?", isPresented: $isCleanupConfirmationPresented, titleVisibility: .visible) {
            Button("Clear Expired Recovery Data", role: .destructive) {
                viewModel.clearExpiredRecoveryData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes recovery data only for completed runs older than \(recoveryRetentionDays) days. You will lose the ability to undo those runs. Your current files and run history are kept. Recovery data for incomplete runs is preserved.")
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(SafeRunTheme.accent)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum SafeRunAbout {
    static var name: String {
        metadata("CFBundleDisplayName") ?? metadata("CFBundleName") ?? ProcessInfo.processInfo.processName
    }
    static var version: String { metadata("CFBundleShortVersionString") ?? "Unavailable" }
    static var build: String { metadata("CFBundleVersion") ?? "Unavailable" }
    static var copyright: String? { metadata("NSHumanReadableCopyright") }

    private static func metadata(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    @MainActor
    static func showPanel() {
        // The native panel reads name, version, icon, and copyright from the app bundle.
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Know what happens before it happens.")
        ])
    }
}
