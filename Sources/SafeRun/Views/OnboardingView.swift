import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var page: Page = .welcome

    private enum Page: Int, CaseIterable {
        case welcome, planning, recovery, connection, ready

        var title: String {
            switch self {
            case .welcome: "SafeRun"
            case .planning: "AI Plans. SafeRun Decides."
            case .recovery: "Built Around Reversibility"
            case .connection: "Connect AI"
            case .ready: "Ready to Run Safely"
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "checkmark.shield.fill"
            case .planning: "list.bullet.clipboard"
            case .recovery: "arrow.uturn.backward.circle.fill"
            case .connection: "key.fill"
            case .ready: "checkmark.circle.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Know what happens before it happens."
            case .planning: "A proposal first. Your approval always."
            case .recovery: "Make room for a change of mind."
            case .connection: "Your account. Your key. Your control."
            case .ready: "Start with one folder and a clear intention."
            }
        }
    }

    var body: some View {
        ZStack {
            SafeRunAtmosphere()
            VStack(spacing: 22) {
                HStack {
                    Text("WELCOME TO SAFERUN")
                        .font(.caption.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(page.rawValue + 1) of \(Page.allCases.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(page == .ready ? SafeRunTheme.safe : SafeRunTheme.accent)
                            .frame(width: 82, height: 82)
                            .safeRunGlassSurface(tint: SafeRunTheme.accent.opacity(0.15), cornerRadius: 25)
                            .accessibilityHidden(true)

                        VStack(spacing: 8) {
                            Text(page.title)
                                .font(.largeTitle.weight(.bold))
                                .accessibilityAddTraits(.isHeader)
                            Text(page.subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)

                        GlassCard(padding: 22) {
                            pageContent
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(4)
                    .id(page)
                    .transition(.opacity)
                }
                .scrollBounceBehavior(.basedOnSize)

                HStack(spacing: 7) {
                    ForEach(Page.allCases, id: \.rawValue) { step in
                        Capsule()
                            .fill(step == page ? SafeRunTheme.accent : Color.secondary.opacity(0.25))
                            .frame(width: step == page ? 22 : 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(page.rawValue + 1) of 5: \(page.title)")

                HStack(spacing: 12) {
                    if page != .welcome {
                        GlassButton(action: { movePage(by: -1) }) {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                    Spacer()
                    if page == .connection && !viewModel.hasAPIKey {
                        Button("Skip AI for Now") { movePage(by: 1) }
                    } else if page != .ready {
                        Button("Set Up Later", action: finish)
                            .help("Open SafeRun now. Reopen this introduction from Help.")
                    }
                    GlassButton(prominence: .prominent, action: {
                        if page == .ready { finish() } else { movePage(by: 1) }
                    }) {
                        Text(page == .ready ? "Open SafeRun" : "Continue")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(30)
        }
        .frame(width: 620, height: 660)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome:
            VStack(alignment: .leading, spacing: 20) {
                feature("Describe the outcome", detail: "Choose a folder and explain the file changes you want.", symbol: "text.bubble")
                feature("See the plan", detail: "Review every proposed operation before anything changes.", symbol: "eye")
                feature("Stay in control", detail: "Simulate, approve, and keep a record of what happened.", symbol: "hand.raised")
            }
        case .planning:
            VStack(alignment: .leading, spacing: 20) {
                feature("AI proposes", detail: "Your instruction and folder metadata help AI build a structured plan. File contents are not uploaded.", symbol: "sparkles")
                feature("SafeRun checks", detail: "Paths, operations, risks, and conflicts are validated and simulated before execution.", symbol: "checkmark.shield")
                feature("You approve", detail: "AI cannot execute commands or control your Mac. Only approved, supported file operations can run.", symbol: "person.crop.circle.badge.checkmark")
            }
        case .recovery:
            VStack(alignment: .leading, spacing: 20) {
                feature("Recovery before changes", detail: "Deleted items and replaced versions are kept in local recovery storage.", symbol: "externaldrive.badge.timemachine")
                feature("Undo from history", detail: "Review completed runs and restore changes while recovery data is available. Conflicts may need your attention.", symbol: "clock.arrow.circlepath")
                feature("Choose when to clean up", detail: "Settings lets you remove expired recovery data for completed runs. Removing it also removes the ability to undo those runs.", symbol: "archivebox")
            }
        case .connection:
            AIConnectionView()
        case .ready:
            VStack(alignment: .leading, spacing: 20) {
                feature("Choose your folder", detail: "SafeRun works within the folder you explicitly authorize.", symbol: "folder.badge.plus")
                feature("Review, simulate, run", detail: "Describe a task, inspect the proposed changes, and simulate before approving execution.", symbol: "play.shield")
                if !viewModel.hasAPIKey {
                    Label("AI setup can wait. Your history, settings, and recovery remain available. Connect later in Settings → AI.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Your key is saved. Use Test Connection in Settings → AI to check access whenever you need.", systemImage: "key")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(SafeRunTheme.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func movePage(by offset: Int) {
        guard let next = Page(rawValue: page.rawValue + offset) else { return }
        withAnimation(reduceMotion ? nil : SafeRunMotion.quick) { page = next }
    }

    private func finish() {
        onboardingCompleted = true
        viewModel.finishOnboarding()
        dismiss()
    }
}
