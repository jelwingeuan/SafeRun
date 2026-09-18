import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("requireSimulation") private var requireSimulation = true
    @AppStorage("confirmDeletes") private var confirmDeletes = true
    @AppStorage("confirmOverwrites") private var confirmOverwrites = true
    @AppStorage("maximumAutomaticActions") private var maximumAutomaticActions = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                pageHeader(
                    eyebrow: "PREFERENCES",
                    title: "Settings",
                    subtitle: "Choose how SafeRun presents and protects every plan.",
                    systemImage: "gearshape"
                )

                Form {
                    Section("General") {
                        Picker("Appearance", selection: $appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        Text("SafeRun follows the system appearance by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Automation") {
                        Toggle("Require simulation before execution", isOn: $requireSimulation)
                        Toggle("Require confirmation for deletes", isOn: $confirmDeletes)
                        Toggle("Require confirmation for overwrites", isOn: $confirmOverwrites)
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

                    Section("Recovery") {
                        LabeledContent("Recovery storage", value: "Managed locally")
                        Toggle("Automatically remove expired recovery data", isOn: .constant(false))
                            .disabled(true)
                        Text("Recovery storage will be enabled with the execution and rollback milestone. SafeRun never sends your files to an external service.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Planner") {
                        LabeledContent("Planner provider", value: "Mock planner")
                        LabeledContent("API configuration", value: "Not configured")
                        Text("The current planner creates structured previews locally. A future provider can be connected without granting shell or terminal access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: 760)
            }
            .padding(.horizontal, SafeRunSpacing.xLarge)
            .padding(.vertical, SafeRunSpacing.xLarge)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }
}
