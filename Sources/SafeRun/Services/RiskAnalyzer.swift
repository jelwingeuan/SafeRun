import Foundation

struct RiskAnalyzer: Sendable {
    func risk(for action: SafeRunAction, context: FolderContext? = nil) -> RiskLevel {
        if action.validationStatus == .failed || action.conflictStatus == .unresolved {
            return .critical
        }

        let baseRisk: RiskLevel
        switch action.type {
        case .createDirectory, .copyFile: baseRisk = .low
        case .moveFile, .renameFile: baseRisk = .medium
        case .replaceFile, .deleteFile: baseRisk = .high
        }

        guard let context else { return baseRisk }

        if let sourceURL = action.sourceURL, !PathValidator.isWithinRoot(sourceURL, root: context.rootFolder) {
            return .critical
        }
        if !PathValidator.isSafeDestination(action.destinationURL, root: context.rootFolder) {
            return .critical
        }
        if action.type == .deleteFile,
           let sourceURL = action.sourceURL,
           context.entries.contains(where: { $0.url.standardizedFileURL == sourceURL.standardizedFileURL && $0.isDirectory }) {
            return .high
        }

        return baseRisk
    }

    func overallRisk(for actions: [SafeRunAction], context: FolderContext? = nil) -> RiskLevel {
        var result = actions.map { risk(for: $0, context: context) }.max() ?? .low
        let moveCount = actions.filter { $0.type == .moveFile }.count
        if moveCount > 100 {
            result = max(result, .high)
        } else if moveCount > 10 {
            result = max(result, .medium)
        }
        return result
    }
}
