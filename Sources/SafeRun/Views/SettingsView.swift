import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("requireSimulation") private var requireSimulation = true
    @AppStorage("confirmDeletes") private var confirmDeletes = true
    @AppStorage("confirmOverwrites") private var confirmOverwrites = true
    @AppStorage("maximumAutomaticActions") private var maximumAutomaticActions = 100

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("General", systemImage: "paintbrush")
            } footer: {
                Text("SafeRun follows the system appearance by default.")
            }

            Section {
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
            } header: {
                Label("Automation", systemImage: "slider.horizontal.3")
            }

            Section {
                LabeledContent("Recovery storage", value: "Managed locally")
                Toggle("Automatically remove expired recovery data", isOn: .constant(false))
                    .disabled(true)
                Text("Recovery storage will be enabled with the execution and rollback milestone. SafeRun never sends your files to an external service.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Recovery", systemImage: "externaldrive.badge.timemachine")
            }

            Section {
                LabeledContent("Planner provider", value: "Mock planner")
                LabeledContent("API configuration", value: "Not configured")
                Text("The current planner creates structured previews locally. A future AI provider can be connected without granting shell or terminal access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("AI", systemImage: "wand.and.stars")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(30)
        .frame(maxWidth: 850, alignment: .leading)
        .navigationTitle("Settings")
    }
}
