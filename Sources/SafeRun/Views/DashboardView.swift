import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel
    @FocusState private var isInstructionFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SafeRunSpacing.xLarge) {
                dashboardHeading
                if !viewModel.interruptedTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("SafeRun detected an interrupted run.", systemImage: "exclamationmark.triangle")
                        Text("Inspect the recovery journal before attempting restoration. SafeRun will not resume execution automatically.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Inspect") { viewModel.selectedSection = .rollbacks }
                    }
                    .padding().background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                if !viewModel.hasAPIKey {
                    HStack {
                        Text("Connect AI to create your first SafeRun automation.")
                        Spacer()
                        Button("Set Up AI") { viewModel.selectedSection = .settings }
                    }
                }
                commandConsole
                recentSimulations
            }
            .padding(.horizontal, SafeRunSpacing.xLarge)
            .padding(.vertical, SafeRunSpacing.xLarge)
            .frame(maxWidth: SafeRunTheme.pageWidth, alignment: .leading)
        }
    }

    private var dashboardHeading: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.small) {
            GlassStatusPill(
                title: "SAFE AUTOMATION SANDBOX",
                systemImage: "checkmark.shield",
                tint: SafeRunTheme.accent
            )
            Text("SafeRun")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Know what happens before it happens.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var commandConsole: some View {
        FloatingGlassPanel(padding: SafeRunSpacing.large, tint: SafeRunTheme.accent.opacity(0.16)) {
            VStack(alignment: .leading, spacing: SafeRunSpacing.large) {
                HStack(alignment: .top, spacing: SafeRunSpacing.medium) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SafeRunTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: SafeRunRadius.control, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("What should SafeRun do?")
                            .font(.title2.weight(.bold))
                        Text("Describe an automation in plain language. SafeRun turns it into a reviewable plan without touching your files.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: SafeRunSpacing.small)

                    GlassStatusPill(
                        title: "Preview only",
                        systemImage: "eye",
                        tint: SafeRunTheme.safe
                    )
                }

                instructionEditor
                FolderDropZone(
                    folder: viewModel.selectedFolder,
                    fileCount: viewModel.folderContext?.fileEntries.count,
                    isScanning: viewModel.isScanning,
                    onChoose: viewModel.chooseFolder,
                    onDropFolder: viewModel.acceptDroppedFolder
                )
                .disabled(viewModel.isBusy)
                if viewModel.isScanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scanned \(viewModel.scannedEntries) items")
                        Button("Cancel", action: viewModel.cancelPendingWork)
                    }
                } else if let context = viewModel.folderContext {
                    FolderScanSummary(context: context)
                    ForEach(context.scanWarnings ?? [], id: \.self) { warning in
                        Text(warning).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Analyze sends your instruction and folder metadata—including filenames—to OpenAI. File contents are never uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
                if viewModel.isAnalyzing {
                    Button("Cancel AI Request", action: viewModel.cancelPendingWork)
                }

                HStack(spacing: SafeRunSpacing.medium) {
                    Label(
                        viewModel.folderContext == nil ? "Select a folder to begin" : "Your files stay untouched until approval",
                        systemImage: viewModel.folderContext == nil ? "folder" : "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer(minLength: SafeRunSpacing.small)

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
                    .help(viewModel.hasAPIKey ? "Send metadata to OpenAI and create a reviewable plan" : "Connect AI in Settings before analyzing")
                }
            }
        }
    }

    private var instructionEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.instruction)
                .font(.body)
                .focused($isInstructionFocused)
                .scrollContentBackground(.hidden)
                .padding(SafeRunSpacing.small)
                .frame(minHeight: 122)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: SafeRunRadius.composer, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SafeRunRadius.composer, style: .continuous)
                        .strokeBorder(
                            isInstructionFocused ? SafeRunTheme.accent.opacity(0.56) : .primary.opacity(0.08),
                            lineWidth: isInstructionFocused ? 1.4 : 1
                        )
                }

            if viewModel.instruction.isEmpty {
                Text("Describe how you want to organize the selected folder.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, SafeRunSpacing.medium)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Automation instruction")
    }

    private var recentSimulations: some View {
        VStack(alignment: .leading, spacing: SafeRunSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent activity")
                        .font(.title3.weight(.bold))
                    Text("Your local, reviewable safety history.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassButton(action: { viewModel.selectedSection = .completedRuns }) {
                    Label("View all", systemImage: "arrow.right")
                }
                .help("View all completed simulations")
            }

            if viewModel.historyItems.isEmpty {
                GlassCard(padding: SafeRunSpacing.medium) {
                    HStack(spacing: SafeRunSpacing.medium) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(SafeRunTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(SafeRunTheme.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your recent activity will appear here")
                                .font(.callout.weight(.medium))
                            Text("Choose a folder and run your first safe analysis.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                let recentItems = Array(viewModel.historyItems.prefix(4))
                VStack(spacing: 0) {
                    ForEach(recentItems) { item in
                        ActivityRow(item: item) {
                            viewModel.openSimulation(item)
                        }
                        if item.id != recentItems.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, SafeRunSpacing.xSmall)
                .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                }
            }
        }
    }
}

private struct FolderScanSummary: View {
    let context: FolderContext

    private var totalBytes: Int64 {
        context.fileEntries.reduce(0) { $0 + $1.byteSize }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(context.fileEntries.count) files")
            Text("·")
            Text("\(context.entries.filter(\.isDirectory).count) folders")
            Text("·")
            Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
            Text("·")
            Text("Scanned")
            Text(context.generatedAt, style: .time)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

func pageHeader(eyebrow: String, title: String, subtitle: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: SafeRunSpacing.medium) {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(SafeRunTheme.accent)
            .frame(width: 40, height: 40)
            .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: SafeRunRadius.control, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.15)
                .foregroundStyle(SafeRunTheme.accent)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
}
