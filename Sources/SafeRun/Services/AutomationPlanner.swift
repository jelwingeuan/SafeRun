import Foundation

protocol AutomationPlanner: Sendable {
    func generatePlan(instruction: String, folderContext: FolderContext) async throws -> SafeRunPlan
}

struct MockAutomationPlanner: AutomationPlanner, Sendable {
    private let riskAnalyzer = RiskAnalyzer()

    func generatePlan(instruction: String, folderContext: FolderContext) async throws -> SafeRunPlan {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else { throw SafeRunError.emptyInstruction }
        try await Task.sleep(for: .milliseconds(260))

        let root = folderContext.rootFolder
        let directFiles = folderContext.fileEntries.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
        }
        let groupedFiles = Dictionary(grouping: directFiles) { category(for: $0.fileExtension) }
        var actions: [SafeRunAction] = []
        var warnings: [String] = []

        for categoryName in ["Images", "Documents", "Archives", "Other"] {
            guard let files = groupedFiles[categoryName], !files.isEmpty else { continue }
            let destinationDirectory = root.appendingPathComponent(categoryName, isDirectory: true)
            let directoryAlreadyExists = folderContext.entries.contains {
                $0.isDirectory && $0.url.standardizedFileURL == destinationDirectory.standardizedFileURL
            }

            if !directoryAlreadyExists {
                actions.append(
                    SafeRunAction(
                        type: .createDirectory,
                        destinationURL: destinationDirectory,
                        filename: categoryName,
                        description: "Create the (categoryName) folder",
                        risk: .low,
                        isReversible: true
                    )
                )
            }

            for file in files {
                let destination = destinationDirectory.appendingPathComponent(file.name)
                actions.append(
                    SafeRunAction(
                        type: .moveFile,
                        sourceURL: file.url,
                        destinationURL: destination,
                        filename: file.name,
                        description: "Move (file.name) into (categoryName)",
                        risk: .medium,
                        isReversible: true
                    )
                )
            }
        }

        if directFiles.isEmpty {
            warnings.append("No top-level files were found. SafeRun created an empty preview so you can inspect the workflow.")
        }
        if !folderContext.duplicateFilenameGroups.isEmpty {
            warnings.append("Duplicate filenames were found in different folders. Destination collisions will be checked during simulation.")
        }

        for index in actions.indices {
            actions[index].risk = riskAnalyzer.risk(for: actions[index], context: folderContext)
        }

        let title = "Organize \(root.lastPathComponent.isEmpty ? "Folder" : root.lastPathComponent)"
        return SafeRunPlan(
            title: title,
            originalInstruction: trimmedInstruction,
            selectedRootFolder: root,
            actions: actions,
            warnings: warnings,
            status: .ready
        )
    }

    private func category(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff": "Images"
        case "pdf", "doc", "docx", "txt", "rtf", "md", "csv", "xls", "xlsx": "Documents"
        case "zip", "7z", "tar", "gz", "dmg": "Archives"
        default: "Other"
        }
    }
}
