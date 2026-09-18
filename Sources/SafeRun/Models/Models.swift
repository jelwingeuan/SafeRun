import Foundation

enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case simulations
    case completedRuns
    case rollbacks
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .simulations: "Simulations"
        case .completedRuns: "Completed Runs"
        case .rollbacks: "Rollbacks"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.3.group.fill"
        case .simulations: "waveform.path.ecg"
        case .completedRuns: "checkmark.circle"
        case .rollbacks: "arrow.uturn.backward.circle"
        case .settings: "gearshape"
        }
    }
}

enum SafeRunActionType: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case createDirectory
    case moveFile
    case copyFile
    case renameFile
    case deleteFile
    case replaceFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createDirectory: "Create"
        case .moveFile: "Move"
        case .copyFile: "Copy"
        case .renameFile: "Rename"
        case .deleteFile: "Delete"
        case .replaceFile: "Replace"
        }
    }

    var description: String {
        switch self {
        case .createDirectory: "Create directory"
        case .moveFile: "Move file"
        case .copyFile: "Copy file"
        case .renameFile: "Rename file"
        case .deleteFile: "Delete file"
        case .replaceFile: "Replace file"
        }
    }

    var systemImage: String {
        switch self {
        case .createDirectory: "folder.badge.plus"
        case .moveFile: "arrow.right"
        case .copyFile: "plus.square.on.square"
        case .renameFile: "pencil"
        case .deleteFile: "trash"
        case .replaceFile: "arrow.triangle.2.circlepath"
        }
    }
}

enum RiskLevel: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    var systemImage: String {
        switch self {
        case .low: "checkmark.shield"
        case .medium: "exclamationmark.shield"
        case .high: "exclamationmark.triangle"
        case .critical: "xmark.octagon"
        }
    }
}

enum ActionValidationStatus: String, Codable, Hashable, Sendable {
    case pending
    case passed
    case failed
}

enum ConflictStatus: String, Codable, Hashable, Sendable {
    case none
    case warning
    case unresolved
}

enum SafeRunPlanStatus: String, Codable, Hashable, Sendable {
    case draft
    case analyzing
    case ready
    case simulating
    case simulationComplete
    case approved
    case executing
    case completed
    case failed
    case rolledBack
}

enum ActionExecutionState: String, Codable, Hashable, Sendable {
    case pending
    case running
    case completed
    case failed
}

struct SafeRunAction: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let type: SafeRunActionType
    let sourceURL: URL?
    let destinationURL: URL?
    let filename: String
    let description: String
    var risk: RiskLevel
    var isReversible: Bool
    var validationStatus: ActionValidationStatus
    var conflictStatus: ConflictStatus
    var executionState: ActionExecutionState
    var confidence: Double?
    var proposedRisk: RiskLevel?

    init(
        id: UUID = UUID(),
        type: SafeRunActionType,
        sourceURL: URL? = nil,
        destinationURL: URL? = nil,
        filename: String,
        description: String,
        risk: RiskLevel,
        isReversible: Bool,
        validationStatus: ActionValidationStatus = .pending,
        conflictStatus: ConflictStatus = .none,
        executionState: ActionExecutionState = .pending,
        confidence: Double? = nil,
        proposedRisk: RiskLevel? = nil
    ) {
        self.id = id
        self.type = type
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.filename = filename
        self.description = description
        self.risk = risk
        self.isReversible = isReversible
        self.validationStatus = validationStatus
        self.conflictStatus = conflictStatus
        self.executionState = executionState
        self.confidence = confidence
        self.proposedRisk = proposedRisk
    }
}

struct SafeRunPlan: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let originalInstruction: String
    let selectedRootFolder: URL
    let generatedAt: Date
    var actions: [SafeRunAction]
    var conflicts: [String]
    var warnings: [String]
    var status: SafeRunPlanStatus
    var rationale: String?
    var estimatedRisk: RiskLevel?

    var totalOperations: Int { actions.count }
    var overallRisk: RiskLevel { actions.map(\.risk).max() ?? .low }
    var reversibleActionCount: Int { actions.filter(\.isReversible).count }
    var affectedFileCount: Int {
        Set(actions.compactMap { $0.sourceURL ?? $0.destinationURL }).count
    }

    init(
        id: UUID = UUID(),
        title: String,
        originalInstruction: String,
        selectedRootFolder: URL,
        generatedAt: Date = .now,
        actions: [SafeRunAction] = [],
        conflicts: [String] = [],
        warnings: [String] = [],
        status: SafeRunPlanStatus = .draft,
        rationale: String? = nil,
        estimatedRisk: RiskLevel? = nil
    ) {
        self.id = id
        self.title = title
        self.originalInstruction = originalInstruction
        self.selectedRootFolder = selectedRootFolder
        self.generatedAt = generatedAt
        self.actions = actions
        self.conflicts = conflicts
        self.warnings = warnings
        self.status = status
        self.rationale = rationale
        self.estimatedRisk = estimatedRisk
    }
}

struct FolderEntry: Identifiable, Codable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let name: String
    let fileExtension: String
    let byteSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let isDirectory: Bool
    let isSymbolicLink: Bool
    var isAlias: Bool? = nil
    var isPackage: Bool? = nil

    var id: String { url.standardizedFileURL.path }
}

struct FolderContext: Codable, Hashable, Sendable {
    let rootFolder: URL
    let entries: [FolderEntry]
    let generatedAt: Date
    var scanWarnings: [String]? = nil

    var fileEntries: [FolderEntry] { entries.filter { !$0.isDirectory } }

    var duplicateFilenameGroups: [[FolderEntry]] {
        Dictionary(grouping: fileEntries, by: { $0.name.lowercased() })
            .values
            .filter { $0.count > 1 }
            .map(Array.init)
    }
}

struct VirtualFileEntry: Identifiable, Codable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    var change: String?

    var id: String { path }
}

struct SimulationResult: Codable, Hashable, Sendable {
    let success: Bool
    let actionsPassed: Int
    let actionsFailed: Int
    let conflicts: [String]
    let warnings: [String]
    let resultingVirtualFilesystem: [VirtualFileEntry]
    let overallRisk: RiskLevel
    let canExecute: Bool
    var snapshot: FileSnapshot? = nil
}

struct RollbackJournalEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let originalActionID: UUID
    let inverseAction: SafeRunAction?
    let recoveryURL: URL?
    let note: String
}

struct RollbackJournal: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let planID: UUID
    let rootFolder: URL
    let createdAt: Date
    let entries: [RollbackJournalEntry]
}

struct ExecutionProgress: Sendable {
    let completedActions: Int
    let totalActions: Int
    let currentAction: String
}

struct ExecutionReport: Sendable {
    let journal: RollbackJournal
    let completedActionIDs: [UUID]
}

struct RunHistoryItem: Codable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    let instruction: String
    let selectedDirectory: URL
    let operationCount: Int
    let risk: RiskLevel
    let result: String
    let rollbackAvailable: Bool
}

enum SafeRunError: LocalizedError, Equatable {
    case folderNotFound
    case selectedItemIsNotDirectory
    case emptyInstruction
    case accessDenied(URL)
    case planNotExecutable(String)
    case invalidPath(URL)
    case executionUnavailable
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderNotFound: "SafeRun could not find that folder."
        case .selectedItemIsNotDirectory: "Select a folder so SafeRun can inspect its contents."
        case .emptyInstruction: "Describe the automation you want SafeRun to preview."
        case .accessDenied(let url): "SafeRun could not access \(url.lastPathComponent). Choose the folder again to grant access."
        case .planNotExecutable(let message): message
        case .invalidPath(let url): "SafeRun blocked an unsafe path: \(url.path)."
        case .executionUnavailable: "Safe execution is not enabled until this plan has passed simulation and received your approval."
        case .executionFailed(let message): message
        }
    }
}
