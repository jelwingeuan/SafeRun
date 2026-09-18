import Foundation
import XCTest
@testable import SafeRun

final class SafeRunTests: XCTestCase {
    func testPathValidatorBlocksTraversalAndSiblingPrefix() {
        let root = URL(fileURLWithPath: "/tmp/SafeRun/Folder", isDirectory: true)
        XCTAssertTrue(PathValidator.isWithinRoot(root.appendingPathComponent("photo.jpg"), root: root))
        XCTAssertFalse(PathValidator.isWithinRoot(root.appendingPathComponent("../Outside"), root: root))
        XCTAssertFalse(PathValidator.isWithinRoot(URL(fileURLWithPath: "/tmp/SafeRun/Folder-copy"), root: root))
        XCTAssertFalse(PathValidator.isSafeDestination(root.appendingPathComponent("../outside"), root: root))
    }

    func testPathValidatorBlocksSymlinkEscape() throws {
        let root = try makeTemporaryFolder()
        let outside = try makeTemporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"),
            withDestinationURL: outside
        )

        XCTAssertFalse(PathValidator.isWithinRoot(root.appendingPathComponent("linked/secret.txt"), root: root))
    }

    func testRiskAnalyzerEscalatesUnsafeAndLargeMoves() {
        let context = FolderContext(rootFolder: URL(fileURLWithPath: "/tmp/root", isDirectory: true), entries: [], generatedAt: .now)
        let unsafe = SafeRunAction(
            type: .moveFile,
            sourceURL: URL(fileURLWithPath: "/tmp/outside.txt"),
            destinationURL: context.rootFolder.appendingPathComponent("inside.txt"),
            filename: "outside.txt",
            description: "Unsafe move",
            risk: .medium,
            isReversible: true
        )
        XCTAssertEqual(RiskAnalyzer().risk(for: unsafe, context: context), .critical)

        let moves = (0..<101).map { index in
            SafeRunAction(
                type: .moveFile,
                sourceURL: context.rootFolder.appendingPathComponent("source-\(index)"),
                destinationURL: context.rootFolder.appendingPathComponent("destination-\(index)"),
                filename: "source-\(index)",
                description: "Move file",
                risk: .medium,
                isReversible: true
            )
        }
        XCTAssertEqual(RiskAnalyzer().overallRisk(for: moves, context: context), .high)
    }

    func testScannerCapturesUnicodeHiddenAndDirectoryMetadata() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appendingPathComponent("résumé.txt"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: false)

        let context = try await FolderContextScanner().scan(root: root)
        XCTAssertEqual(context.fileEntries.count, 2)
        XCTAssertTrue(context.entries.contains { $0.name == "Empty" && $0.isDirectory })
        XCTAssertTrue(context.entries.contains { $0.name == "résumé.txt" && $0.fileExtension == "txt" })
        XCTAssertTrue(context.entries.contains { $0.name == ".hidden" })
    }

    func testSimulationDetectsMissingSourceAndDestinationCollisionWithoutWriting() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("photo.jpg")
        try Data("image".utf8).write(to: source)
        let context = try await FolderContextScanner().scan(root: root)
        let destination = root.appendingPathComponent("Images/photo.jpg")
        let plan = SafeRunPlan(
            title: "Test plan",
            originalInstruction: "Move files",
            selectedRootFolder: root,
            actions: [
                SafeRunAction(type: .createDirectory, destinationURL: root.appendingPathComponent("Images", isDirectory: true), filename: "Images", description: "Create Images", risk: .low, isReversible: true),
                SafeRunAction(type: .moveFile, sourceURL: source, destinationURL: destination, filename: "photo.jpg", description: "Move photo", risk: .medium, isReversible: true),
                SafeRunAction(type: .moveFile, sourceURL: URL(fileURLWithPath: "/does/not/exist"), destinationURL: destination, filename: "missing.jpg", description: "Move missing", risk: .medium, isReversible: true)
            ]
        )

        let result = await SimulationEngine().simulate(plan: plan, context: context)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.actionsPassed, 2)
        XCTAssertEqual(result.actionsFailed, 1)
        XCTAssertFalse(result.conflicts.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Simulation must not touch the real filesystem")
    }

    func testSimulationDetectsMissingDestinationDirectory() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("photo.jpg")
        try Data("image".utf8).write(to: source)
        let context = try await FolderContextScanner().scan(root: root)
        let plan = SafeRunPlan(
            title: "Missing destination",
            originalInstruction: "Move file",
            selectedRootFolder: root,
            actions: [SafeRunAction(
                type: .moveFile,
                sourceURL: source,
                destinationURL: root.appendingPathComponent("Missing/photo.jpg"),
                filename: "photo.jpg",
                description: "Move photo",
                risk: .medium,
                isReversible: true
            )]
        )

        let result = await SimulationEngine().simulate(plan: plan, context: context)
        XCTAssertFalse(result.canExecute)
        XCTAssertTrue(result.conflicts.contains { $0.contains("destination folder") })
    }

    func testMockPlannerProducesStructuredActionsForFiles() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("image".utf8).write(to: root.appendingPathComponent("photo.png"))
        try Data("document".utf8).write(to: root.appendingPathComponent("invoice.pdf"))
        let context = try await FolderContextScanner().scan(root: root)

        let plan = try await MockAutomationPlanner().generatePlan(
            instruction: "Organize by file type",
            folderContext: context
        )
        XCTAssertEqual(plan.status, .ready)
        XCTAssertTrue(plan.actions.contains { $0.type == .createDirectory })
        XCTAssertTrue(plan.actions.contains { $0.type == .moveFile && $0.filename == "photo.png" })
        XCTAssertTrue(plan.actions.allSatisfy { $0.sourceURL.map { PathValidator.isWithinRoot($0, root: root) } ?? true })
    }

    func testRollbackManagerGeneratesInverseMoveRenameAndCopyActions() {
        let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let source = root.appendingPathComponent("a.txt")
        let destination = root.appendingPathComponent("b.txt")
        let plan = SafeRunPlan(
            title: "Rollback test",
            originalInstruction: "Test",
            selectedRootFolder: root,
            actions: [
                SafeRunAction(type: .moveFile, sourceURL: source, destinationURL: destination, filename: "a.txt", description: "Move", risk: .medium, isReversible: true),
                SafeRunAction(type: .copyFile, sourceURL: source, destinationURL: destination, filename: "a.txt", description: "Copy", risk: .low, isReversible: true)
            ]
        )

        let journal = RollbackManager().makeJournal(for: plan)
        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertEqual(journal.entries[0].inverseAction?.sourceURL, destination)
        XCTAssertEqual(journal.entries[0].inverseAction?.destinationURL, source)
        XCTAssertEqual(journal.entries[1].inverseAction?.type, .deleteFile)
    }

    func testExecutionGateRequiresSimulationAndExplicitApproval() throws {
        let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let plan = SafeRunPlan(title: "Test", originalInstruction: "Test", selectedRootFolder: root, status: .simulationComplete)
        let result = SimulationResult(success: true, actionsPassed: 0, actionsFailed: 0, conflicts: [], warnings: [], resultingVirtualFilesystem: [], overallRisk: .low, canExecute: true)

        XCTAssertThrowsError(try SafeExecutionEngine().validateApproval(plan: plan, simulation: result, userApproved: false))
        XCTAssertNoThrow(try SafeExecutionEngine().validateApproval(plan: plan, simulation: result, userApproved: true))
    }

    func testExecutionMovesFilesAndRollbackRestoresThem() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("photo.jpg")
        let destinationFolder = root.appendingPathComponent("Images", isDirectory: true)
        let destination = destinationFolder.appendingPathComponent("photo.jpg")
        try Data("image".utf8).write(to: source)

        let plan = SafeRunPlan(
            title: "Move photo",
            originalInstruction: "Move photo into Images",
            selectedRootFolder: root,
            actions: [
                SafeRunAction(
                    type: .createDirectory,
                    destinationURL: destinationFolder,
                    filename: "Images",
                    description: "Create Images",
                    risk: .low,
                    isReversible: true
                ),
                SafeRunAction(
                    type: .moveFile,
                    sourceURL: source,
                    destinationURL: destination,
                    filename: "photo.jpg",
                    description: "Move photo.jpg",
                    risk: .medium,
                    isReversible: true
                )
            ],
            status: .simulationComplete
        )

        let simulation = await SimulationEngine().simulate(
            plan: plan,
            context: try await FolderContextScanner().scan(root: root)
        )
        XCTAssertTrue(simulation.canExecute)

        let engine = SafeExecutionEngine()
        let report = try await engine.execute(plan: plan, simulation: simulation, userApproved: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        try await engine.rollback(report.journal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationFolder.path))
    }

    func testExecutionMovesDeletedFileToRecoveryAndRestoresIt() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("remove-me.txt")
        try Data("recover me".utf8).write(to: source)
        let plan = SafeRunPlan(
            title: "Delete file",
            originalInstruction: "Delete remove-me.txt",
            selectedRootFolder: root,
            actions: [
                SafeRunAction(
                    type: .deleteFile,
                    sourceURL: source,
                    filename: "remove-me.txt",
                    description: "Delete remove-me.txt",
                    risk: .high,
                    isReversible: true
                )
            ],
            status: .simulationComplete
        )

        let simulation = await SimulationEngine().simulate(
            plan: plan,
            context: try await FolderContextScanner().scan(root: root)
        )
        XCTAssertTrue(simulation.canExecute)

        let engine = SafeExecutionEngine()
        let report = try await engine.execute(plan: plan, simulation: simulation, userApproved: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(report.journal.entries.first?.recoveryURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)

        try await engine.rollback(report.journal)
        XCTAssertEqual(try String(contentsOf: source), "recover me")
        XCTAssertFalse(report.journal.entries.contains { entry in
            guard let recoveryURL = entry.recoveryURL else { return false }
            return FileManager.default.fileExists(atPath: recoveryURL.path)
        })
    }

    func testExecutionReplacesDestinationAndRollbackRestoresPreviousContent() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("new.txt")
        let destination = root.appendingPathComponent("existing.txt")
        try Data("new content".utf8).write(to: source)
        try Data("old content".utf8).write(to: destination)

        let plan = SafeRunPlan(
            title: "Replace file",
            originalInstruction: "Replace existing.txt",
            selectedRootFolder: root,
            actions: [
                SafeRunAction(
                    type: .replaceFile,
                    sourceURL: source,
                    destinationURL: destination,
                    filename: "existing.txt",
                    description: "Replace existing.txt",
                    risk: .high,
                    isReversible: true
                )
            ],
            status: .simulationComplete
        )

        let simulation = await SimulationEngine().simulate(
            plan: plan,
            context: try await FolderContextScanner().scan(root: root)
        )
        XCTAssertTrue(simulation.canExecute)

        let engine = SafeExecutionEngine()
        let report = try await engine.execute(plan: plan, simulation: simulation, userApproved: true)
        XCTAssertEqual(try String(contentsOf: source), "new content")
        XCTAssertEqual(try String(contentsOf: destination), "new content")

        try await engine.rollback(report.journal)
        XCTAssertEqual(try String(contentsOf: source), "new content")
        XCTAssertEqual(try String(contentsOf: destination), "old content")
    }

    func testExecutionAutomaticallyRollsBackEarlierChangesWhenLaterSourceDisappears() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstSource = root.appendingPathComponent("first.txt")
        let secondSource = root.appendingPathComponent("second.txt")
        let firstDestination = root.appendingPathComponent("first-moved.txt")
        let secondDestination = root.appendingPathComponent("second-moved.txt")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let plan = SafeRunPlan(
            title: "Move two files",
            originalInstruction: "Move both files",
            selectedRootFolder: root,
            actions: [
                SafeRunAction(
                    type: .moveFile,
                    sourceURL: firstSource,
                    destinationURL: firstDestination,
                    filename: "first.txt",
                    description: "Move first.txt",
                    risk: .medium,
                    isReversible: true
                ),
                SafeRunAction(
                    type: .moveFile,
                    sourceURL: secondSource,
                    destinationURL: secondDestination,
                    filename: "second.txt",
                    description: "Move second.txt",
                    risk: .medium,
                    isReversible: true
                )
            ],
            status: .simulationComplete
        )

        let simulation = await SimulationEngine().simulate(
            plan: plan,
            context: try await FolderContextScanner().scan(root: root)
        )
        XCTAssertTrue(simulation.canExecute)
        try FileManager.default.removeItem(at: secondSource)

        do {
            _ = try await SafeExecutionEngine().execute(plan: plan, simulation: simulation, userApproved: true)
            XCTFail("Execution should fail when the filesystem changes after simulation.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("rolled back"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSource.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path))
    }

    private func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SafeRunTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
