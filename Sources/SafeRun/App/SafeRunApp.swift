import SwiftUI

@main
struct SafeRunApp: App {
    @StateObject private var viewModel = SafeRunViewModel()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .frame(minWidth: 1_080, minHeight: 700)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Folder") {
                    viewModel.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
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
