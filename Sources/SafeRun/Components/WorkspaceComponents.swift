import SwiftUI

enum SafeRunSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let regular: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let xxLarge: CGFloat = 48
}

enum SafeRunRadius {
    static let control: CGFloat = 9
    static let row: CGFloat = 11
    static let panel: CGFloat = 16
    static let composer: CGFloat = 20
}

extension ActionValidationStatus {
    var title: String {
        switch self {
        case .pending: "Pending"
        case .passed: "Passed"
        case .failed: "Needs review"
        }
    }
}

extension ActionExecutionState {
    var title: String {
        switch self {
        case .pending: "Pending"
        case .running: "Executing"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

struct WorkspaceHeader: View {
    let title: String
    let subtitle: String
    var risk: RiskLevel?
    var statusTitle: String?
    var statusImage: String = "circle"
    var statusTint: Color = SafeRunTheme.accent

    var body: some View {
        HStack(alignment: .top, spacing: SafeRunSpacing.regular) {
            VStack(alignment: .leading, spacing: SafeRunSpacing.small) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: SafeRunSpacing.regular)

            HStack(spacing: SafeRunSpacing.small) {
                if let statusTitle {
                    GlassStatusPill(title: statusTitle, systemImage: statusImage, tint: statusTint)
                }
                if let risk {
                    RiskBadge(risk: risk)
                }
            }
        }
    }
}

struct OperationSummaryStrip: View {
    let plan: SafeRunPlan
    var result: SimulationResult?

    private var moves: Int {
        plan.actions.filter { $0.type == .moveFile || $0.type == .copyFile }.count
    }

    private var renames: Int {
        plan.actions.filter { $0.type == .renameFile }.count
    }

    private var creates: Int {
        plan.actions.filter { $0.type == .createDirectory }.count
    }

    private var deletes: Int {
        plan.actions.filter { $0.type == .deleteFile || $0.type == .replaceFile }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            SummaryValue(title: "Actions", value: "\(plan.totalOperations)", tint: SafeRunTheme.accent)
            summaryDivider
            SummaryValue(title: "Moves", value: "\(moves)", tint: SafeRunTheme.accent)
            summaryDivider
            SummaryValue(title: "Renames", value: "\(renames)", tint: SafeRunTheme.accent)
            summaryDivider
            SummaryValue(title: "Creates", value: "\(creates)", tint: SafeRunTheme.safe)
            summaryDivider
            SummaryValue(title: "Deletes", value: "\(deletes)", tint: deletes > 0 ? SafeRunTheme.caution : .secondary)

            if let result {
                Spacer(minLength: SafeRunSpacing.regular)
                summaryDivider
                SummaryValue(
                    title: "Passed",
                    value: "\(result.actionsPassed)",
                    tint: result.success ? SafeRunTheme.safe : SafeRunTheme.caution
                )
            }
        }
        .padding(.horizontal, SafeRunSpacing.regular)
        .padding(.vertical, SafeRunSpacing.medium)
        .safeRunGlassSurface(tint: SafeRunTheme.accent.opacity(0.10), cornerRadius: SafeRunRadius.panel)
    }

    private var summaryDivider: some View {
        Divider()
            .frame(height: 24)
            .padding(.horizontal, SafeRunSpacing.medium)
    }
}

private struct SummaryValue: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 58, alignment: .leading)
    }
}

enum OperationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case moves = "Moves"
    case renames = "Renames"
    case creates = "Creates"
    case deletes = "Deletes"
    case conflicts = "Conflicts"

    var id: String { rawValue }

    func matches(_ action: SafeRunAction) -> Bool {
        switch self {
        case .all: true
        case .moves: action.type == .moveFile || action.type == .copyFile
        case .renames: action.type == .renameFile
        case .creates: action.type == .createDirectory
        case .deletes: action.type == .deleteFile || action.type == .replaceFile
        case .conflicts: action.validationStatus == .failed || action.conflictStatus == .unresolved
        }
    }
}

struct OperationFilterBar: View {
    @Binding var filter: OperationFilter
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: SafeRunSpacing.medium) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SafeRunSpacing.xSmall) {
                    ForEach(OperationFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(filter == option ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    filter == option ? SafeRunTheme.accent.opacity(0.14) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
                .padding(4)
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: SafeRunRadius.control, style: .continuous))

            HStack(spacing: SafeRunSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                    .accessibilityLabel("Search operations")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: SafeRunRadius.control, style: .continuous))
        }
    }
}

struct ConflictBanner: View {
    let count: Int
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: SafeRunSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SafeRunTheme.caution)
            Text("\(count) conflict\(count == 1 ? "" : "s") require attention.")
                .font(.callout.weight(.medium))
            Spacer(minLength: SafeRunSpacing.small)
            Button("Review Conflicts", action: onReview)
                .buttonStyle(.link)
                .tint(SafeRunTheme.caution)
        }
        .padding(.horizontal, SafeRunSpacing.medium)
        .padding(.vertical, SafeRunSpacing.small)
        .background(SafeRunTheme.caution.opacity(0.09), in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous)
                .strokeBorder(SafeRunTheme.caution.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OperationTable: View {
    let actions: [SafeRunAction]
    let selectedActionID: UUID?
    let onSelect: (SafeRunAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableHeader
                ForEach(actions) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        OperationTableRow(action: action, isSelected: selectedActionID == action.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 760, alignment: .leading)
        }
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SafeRunRadius.panel, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: SafeRunSpacing.medium) {
            Text("Action")
                .frame(width: 110, alignment: .leading)
            Text("Item")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("Destination")
                .frame(width: 210, alignment: .leading)
            Text("Risk")
                .frame(width: 96, alignment: .leading)
            Text("Status")
                .frame(width: 116, alignment: .leading)
        }
        .font(.caption2.weight(.bold))
        .tracking(0.8)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, SafeRunSpacing.medium)
        .padding(.vertical, SafeRunSpacing.small)
    }
}

private struct OperationTableRow: View {
    @State private var isHovering = false

    let action: SafeRunAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SafeRunSpacing.medium) {
            Label(action.type.title, systemImage: action.type.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SafeRunTheme.accent)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(action.sourceURL?.path ?? "New directory")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            Text(action.destinationURL?.path ?? "—")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 210, alignment: .leading)

            RiskBadge(risk: action.risk)
                .frame(width: 96, alignment: .leading)

            ActionStatusBadge(action: action)
                .frame(width: 116, alignment: .leading)
        }
        .padding(.horizontal, SafeRunSpacing.medium)
        .padding(.vertical, SafeRunSpacing.small)
        .background(
            isSelected ? SafeRunTheme.accent.opacity(0.11) : (isHovering ? Color.primary.opacity(0.045) : Color.clear),
            in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous)
                    .strokeBorder(SafeRunTheme.accent.opacity(0.2), lineWidth: 1)
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.type.title), \(action.filename), \(action.risk.title) risk, \(action.validationStatus.title)")
    }
}

private struct ActionStatusBadge: View {
    let action: SafeRunAction

    private var title: String {
        switch action.executionState {
        case .pending:
            action.validationStatus.title
        case .running, .completed, .failed:
            action.executionState.title
        }
    }

    private var image: String {
        switch action.executionState {
        case .pending:
            switch action.validationStatus {
            case .pending: "circle.dashed"
            case .passed: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            }
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch action.executionState {
        case .pending:
            switch action.validationStatus {
            case .pending: .secondary
            case .passed: SafeRunTheme.safe
            case .failed: SafeRunTheme.danger
            }
        case .running: SafeRunTheme.accent
        case .completed: SafeRunTheme.safe
        case .failed: SafeRunTheme.danger
        }
    }

    var body: some View {
        Label(title, systemImage: image)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
    }
}

struct ActivityRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let item: RunHistoryItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: SafeRunSpacing.medium) {
                Image(systemName: item.rollbackAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.rollbackAvailable ? SafeRunTheme.safe : SafeRunTheme.caution)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.selectedDirectory.lastPathComponent).font(.callout.weight(.medium))
                    Text(item.result).font(.caption).foregroundStyle(.secondary)
                }
                    .lineLimit(2)
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

                Text("\(item.operationCount) actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)

                RiskBadge(risk: item.risk)
                    .frame(width: 100, alignment: .leading)

                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isHovering ? SafeRunTheme.accent : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, SafeRunSpacing.medium)
            .padding(.vertical, SafeRunSpacing.medium)
            .background(isHovering ? Color.primary.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: SafeRunRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : SafeRunMotion.quick, value: isHovering)
        .accessibilityLabel("\(item.selectedDirectory.lastPathComponent), \(item.operationCount) actions, \(item.risk.title) risk")
    }
}
