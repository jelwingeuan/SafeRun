import Foundation

protocol AutomationPlanner: Sendable {
    func generatePlan(instruction: String, folderContext: FolderContext) async throws -> SafeRunPlan
}
