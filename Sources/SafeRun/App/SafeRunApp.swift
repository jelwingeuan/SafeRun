import SwiftUI

@main
struct SafeRunApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = SafeRunViewModel()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(viewModel)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .frame(minWidth: 1_080, minHeight: 700)
        }
        .defaultSize(width: 1_280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(SafeRunAbout.name)") { SafeRunAbout.showPanel() }
            }
            CommandGroup(after: .newItem) {
                Button("Choose Folder") {
                    viewModel.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Welcome to SafeRun") {
                    openWindow(id: "main")
                    viewModel.isOnboardingPresented = true
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .background { SafeRunAtmosphere() }
                .frame(width: 760, height: 700)
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
