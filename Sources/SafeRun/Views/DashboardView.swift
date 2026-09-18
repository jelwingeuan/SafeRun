import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var viewModel: SafeRunViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                pageHeader(
                    eyebrow: "SAFE AUTOMATION SANDBOX",
                    title: "Dashboard",
                    subtitle: "Know what happens before it happens.",
                    systemImage: "checkmark.shield"
                )

                SafeRunCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("What should SafeRun do?")
                                    .font(.title2.weight(.bold))
                                Text("Describe the file automation in plain language. SafeRun will turn it into a reviewable plan without touching your files.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.title2)
                                .foregroundStyle(SafeRunPalette.accent)
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.instruction)
                                .font(.body)
                                .frame(minHeight: 82)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if viewModel.instruction.isEmpty {
                                Text("Organize this folder by file type and move duplicates into a Duplicates folder.")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 19)
                                    .padding(.vertical, 17)
                                    .allowsHitTesting(false)
                            }
                        }

                        FolderDropZone(
                            folder: viewModel.selectedFolder,
                            isScanning: viewModel.isScanning,
                            onChoose: viewModel.chooseFolder,
                            onDropFolder: viewModel.acceptDroppedFolder
                        )

                        HStack {
                            Label("Preview only until you approve a plan", systemImage: "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                viewModel.analyze()
                            } label: {
                                if viewModel.isAnalyzing {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Analyzing…")
                                } else {
                                    Label("Analyze", systemImage: "arrow.right")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!viewModel.canAnalyze)
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Recent simulations")
                            .font(.title3.weight(.bold))
                        Spacer()
                        Button("View all") {
                            viewModel.selectedSection = .simulations
                        }
                        .buttonStyle(.link)
                    }

                    if viewModel.historyItems.isEmpty {
                        HStack(spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(SafeRunPalette.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your previews will appear here")
                                    .font(.body.weight(.medium))
                                Text("Choose a folder and run your first safe analysis.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(18)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                            ForEach(viewModel.historyItems.prefix(3)) { item in
                                HistoryCard(item: item) {
                                    viewModel.openSimulation(item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 1_020, alignment: .leading)
        }
    }
}

struct HistoryCard: View {
    let item: RunHistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(SafeRunPalette.accent)
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
                    Text(item.result)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

func pageHeader(eyebrow: String, title: String, subtitle: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 15) {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .foregroundStyle(SafeRunPalette.accent)
            .frame(width: 44, height: 44)
            .background(SafeRunPalette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(SafeRunPalette.accent)
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
}
