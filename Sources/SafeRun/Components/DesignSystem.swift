import SwiftUI
import UniformTypeIdentifiers

enum SafeRunPalette {
    static let accent = SafeRunTheme.accent
    static let accentSoft = SafeRunTheme.accentSoft
    static let mint = SafeRunTheme.safe
    static let warm = SafeRunTheme.caution
}

struct SafeRunCard<Content: View>: View {
    private let content: Content
    var padding: CGFloat = 20

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        GlassCard(padding: padding) {
            content
        }
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Label("\(risk.title) Risk", systemImage: risk.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(risk.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(risk.tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(risk.tint.opacity(0.16), lineWidth: 1)
            }
            .accessibilityLabel("Risk: \(risk.title)")
    }
}

struct ActionBadge: View {
    let type: SafeRunActionType

    var body: some View {
        Label(type.title, systemImage: type.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(SafeRunTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(SafeRunTheme.accentSoft, in: Capsule())
    }
}

struct SummaryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = SafeRunTheme.accent

    var body: some View {
        GlassCard(padding: 15, tint: tint.opacity(0.18)) {
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
        .frame(minWidth: 126, alignment: .leading)
    }
}

struct OperationRow: View {
    let action: SafeRunAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: action.type.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(SafeRunTheme.accent)
                .frame(width: 34, height: 34)
                .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(action.description)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if action.validationStatus == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(SafeRunTheme.danger)
                            .accessibilityLabel("Validation failed")
                    }
                }
                Text(action.destinationURL?.path ?? action.sourceURL?.path ?? action.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)
            ActionBadge(type: action.type)
            RiskBadge(risk: action.risk)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isSelected ? SafeRunTheme.accent.opacity(0.105) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SafeRunTheme.accent.opacity(0.18), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.type.title), \(action.filename), \(action.risk.title) risk")
    }
}

struct FolderDropZone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let folder: URL?
    let fileCount: Int?
    let isScanning: Bool
    let onChoose: () -> Void
    let onDropFolder: (URL) -> Void
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: SafeRunSpacing.medium) {
            Image(systemName: folder == nil ? "folder.badge.plus" : "folder.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SafeRunTheme.accent)
                .frame(width: 38, height: 38)
                .background(SafeRunTheme.accentSoft, in: RoundedRectangle(cornerRadius: SafeRunRadius.control, style: .continuous))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                if let folder {
                    Text(folder.lastPathComponent)
                        .font(.body.weight(.semibold))
                    Text(isScanning ? "Reading folder metadata…" : "\(fileCount ?? 0) files ready to preview")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isScanning ? .secondary : SafeRunTheme.safe)
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                } else {
                    Text(isTargeted ? "Drop the folder to inspect it" : "Drop a folder here")
                        .font(.body.weight(.semibold))
                    Text("or choose one from Finder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: SafeRunSpacing.small)

            GlassButton(action: onChoose) {
                Label(folder == nil ? "Attach Folder" : "Change Folder", systemImage: "folder")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, SafeRunSpacing.medium)
        .background(
            (isTargeted ? SafeRunTheme.accent.opacity(0.10) : Color.primary.opacity(0.035)),
            in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous)
                .strokeBorder(
                    SafeRunTheme.accent.opacity(isTargeted ? 0.75 : 0.24),
                    style: StrokeStyle(lineWidth: isTargeted ? 1.6 : 1.1, dash: [7, 6])
                )
        }
        .scaleEffect(isTargeted && !reduceMotion ? 1.012 : 1)
        .animation(reduceMotion ? nil : SafeRunMotion.quick, value: isTargeted)
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
                .foregroundStyle(SafeRunTheme.accent)
                .frame(width: 60, height: 60)
                .background(SafeRunTheme.accentSoft, in: Circle())
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                GlassButton(prominence: .prominent, action: action) {
                    Text(actionTitle)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(28)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(SafeRunTheme.accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : SafeRunMotion.quick, value: configuration.isPressed)
    }
}
