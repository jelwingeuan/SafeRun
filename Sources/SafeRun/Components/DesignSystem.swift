import SwiftUI
import UniformTypeIdentifiers

enum SafeRunPalette {
    static let accent = Color(red: 0.18, green: 0.47, blue: 0.95)
    static let accentSoft = Color(red: 0.18, green: 0.47, blue: 0.95).opacity(0.12)
    static let mint = Color(red: 0.18, green: 0.67, blue: 0.49)
    static let warm = Color(red: 0.95, green: 0.63, blue: 0.20)
}

struct SafeRunCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 20

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    private var color: Color {
        switch risk {
        case .low: SafeRunPalette.mint
        case .medium: SafeRunPalette.warm
        case .high: .orange
        case .critical: .red
        }
    }

    var body: some View {
        Label(risk.title, systemImage: risk.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.13), in: Capsule())
            .accessibilityLabel("Risk: \(risk.title)")
    }
}

struct ActionBadge: View {
    let type: SafeRunActionType

    var body: some View {
        Label(type.title, systemImage: type.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SafeRunPalette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SafeRunPalette.accentSoft, in: Capsule())
    }
}

struct SummaryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = SafeRunPalette.accent

    var body: some View {
        SafeRunCard(padding: 15) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 118, alignment: .leading)
    }
}

struct OperationRow: View {
    let action: SafeRunAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: action.type.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(SafeRunPalette.accent)
                .frame(width: 34, height: 34)
                .background(SafeRunPalette.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(action.description)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if action.validationStatus == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Validation failed")
                    }
                }
                Text(action.destinationURL?.path ?? action.sourceURL?.path ?? action.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            ActionBadge(type: action.type)
            RiskBadge(risk: action.risk)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(isSelected ? SafeRunPalette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.type.title), \(action.filename), \(action.risk.title) risk")
    }
}

struct FolderDropZone: View {
    let folder: URL?
    let isScanning: Bool
    let onChoose: () -> Void
    let onDropFolder: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: folder == nil ? "folder.badge.plus" : "folder.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(SafeRunPalette.accent)
                .frame(width: 56, height: 56)
                .background(SafeRunPalette.accentSoft, in: Circle())

            if let folder {
                Text(folder.lastPathComponent)
                    .font(.body.weight(.semibold))
                Text(isScanning ? "Reading folder metadata…" : folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Choose a folder to preview")
                    .font(.body.weight(.semibold))
                Text("Drop a folder here, or choose one from Finder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(folder == nil ? "Select Folder" : "Change Folder", action: onChoose)
                .buttonStyle(.bordered)
                .tint(SafeRunPalette.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 168)
        .padding(.horizontal, 24)
        .background(isTargeted ? SafeRunPalette.accentSoft : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SafeRunPalette.accent.opacity(isTargeted ? 0.85 : 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in onDropFolder(url) }
            }
            return true
        }
        .accessibilityLabel(folder == nil ? "Folder drop zone" : "Selected folder \(folder!.lastPathComponent)")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(SafeRunPalette.accent)
                .frame(width: 60, height: 60)
                .background(SafeRunPalette.accentSoft, in: Circle())
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(SafeRunPalette.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(28)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(SafeRunPalette.accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
