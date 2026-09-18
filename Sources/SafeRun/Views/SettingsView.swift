import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("requireSimulation") private var requireSimulation = true
    @AppStorage("confirmDeletes") private var confirmDeletes = true
    @AppStorage("confirmOverwrites") private var confirmOverwrites = true
    @AppStorage("maximumAutomaticActions") private var maximumAutomaticActions = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader(
                    eyebrow: "PREFERENCES",
                    title: "Settings",
                    subtitle: "Choose how SafeRun presents and protects every plan.",
                    systemImage: "gearshape"
                )

                settingsCard(title: "General", symbol: "paintbrush", tint: SafeRunTheme.accent) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Appearance")
                            .font(.callout.weight(.medium))
                        Picker("Appearance", selection: $appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("SafeRun follows the system appearance by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard(title: "Automation", symbol: "slider.horizontal.3", tint: SafeRunTheme.accent) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Require simulation before execution", isOn: $requireSimulation)
                        Toggle("Require confirmation for deletes", isOn: $confirmDeletes)
                        Toggle("Require confirmation for overwrites", isOn: $confirmOverwrites)
                        Divider()
                        Stepper(value: $maximumAutomaticActions, in: 1...10_000, step: 10) {
                            HStack {
                                Text("Maximum automatic actions")
                                Spacer()
                                Text("\(maximumAutomaticActions)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                settingsCard(title: "Recovery", symbol: "externaldrive.badge.timemachine", tint: SafeRunTheme.safe) {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsValue("Recovery storage", value: "Managed locally")
                        Toggle("Automatically remove expired recovery data", isOn: .constant(false))
                            .disabled(true)
                        Text("Recovery storage will be enabled with the execution and rollback milestone. SafeRun never sends your files to an external service.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard(title: "AI", symbol: "wand.and.stars", tint: SafeRunTheme.caution) {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsValue("Planner provider", value: "Mock planner")
                        settingsValue("API configuration", value: "Not configured")
                        Text("The current planner creates structured previews locally. A future AI provider can be connected without granting shell or terminal access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(padding: 20, tint: tint.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                content()
            }
        }
    }

    private func settingsValue(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
