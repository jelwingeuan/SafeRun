import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @FocusState private var isInstructionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                dashboardHeading
                commandConsole
                recentSimulations
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .frame(maxWidth: SafeRunTheme.pageWidth, alignment: .leading)
        }
    }

    private var dashboardHeading: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassStatusPill(
                title: "SAFE AUTOMATION SANDBOX",
                systemImage: "checkmark.shield",
                tint: SafeRunTheme.accent
            )
            Text("SafeRun")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Know what happens before it happens.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var commandConsole: some View {
        FloatingGlassPanel(padding: 28, tint: SafeRunTheme.accent.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SafeRunTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("What should SafeRun do?")
                            .font(.title2.weight(.bold))
                        Text("Describe an automation in plain language. SafeRun turns it into a reviewable plan without touching your files.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    GlassStatusPill(
                        title: "Preview only",
                        systemImage: "eye",
                        tint: SafeRunTheme.safe
                    )
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.instruction)
                        .font(.body)
                        .focused($isInstructionFocused)
                        .scrollContentBackground(.hidden)
                        .padding(13)
                        .frame(minHeight: 122)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    isInstructionFocused ? SafeRunTheme.accent.opacity(0.56) : .primary.opacity(0.08),
                                    lineWidth: isInstructionFocused ? 1.4 : 1
                                )
                        }

                    if viewModel.instruction.isEmpty {
                        Text("Organize this folder by file type and move duplicates into a Duplicates folder.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

                FolderDropZone(
                    folder: viewModel.selectedFolder,
                    fileCount: viewModel.folderContext?.fileEntries.count,
                    isScanning: viewModel.isScanning,
                    onChoose: viewModel.chooseFolder,
                    onDropFolder: viewModel.acceptDroppedFolder
                )

                HStack(spacing: 14) {
                    Label(
                        viewModel.folderContext == nil ? "Select a folder to begin" : "Your real files stay untouched until a future approval step",
                        systemImage: viewModel.folderContext == nil ? "folder" : "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    GlassButton(
                        prominence: .prominent,
                        isDisabled: !viewModel.canAnalyze,
                        action: viewModel.analyze
                    ) {
                        HStack(spacing: 7) {
                            if viewModel.isAnalyzing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(viewModel.isAnalyzing ? "Analyzing…" : "Analyze", systemImage: "arrow.right")
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
    }

    private var recentSimulations: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent simulations")
                        .font(.title3.weight(.bold))
                    Text("Your local, reviewable safety history.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassButton(action: { viewModel.selectedSection = .simulations }) {
                    Label("View all", systemImage: "arrow.right")
                }
            }

            if viewModel.historyItems.isEmpty {
                GlassCard(padding: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundStyle(SafeRunTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(SafeRunTheme.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your previews will appear here")
                                .font(.body.weight(.medium))
                            Text("Choose a folder and run your first safe analysis.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.historyItems.prefix(3)) { item in
                        HistoryCard(item: item) {
                            viewModel.openSimulation(item)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let item: RunHistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            InteractiveGlassCard(padding: 18, tint: item.risk.tint.opacity(0.15)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: item.rollbackAvailable ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(item.rollbackAvailable ? SafeRunTheme.safe : SafeRunTheme.caution)
                        Spacer()
                        RiskBadge(risk: item.risk)
                    }
                    Text(item.selectedDirectory.lastPathComponent)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(item.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack {
                        Text("\(item.operationCount) operations")
                        Spacer()
                        Text(item.timestamp, style: .relative)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    if isHovering {
                        Label("View details", systemImage: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SafeRunTheme.accent)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : SafeRunMotion.quick, value: isHovering)
    }
}

func pageHeader(eyebrow: String, title: String, subtitle: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 15) {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .foregroundStyle(SafeRunTheme.accent)
            .frame(width: 44, height: 44)
            .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.15)
                .foregroundStyle(SafeRunTheme.accent)
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
}
