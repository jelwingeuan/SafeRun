import Foundation
import XCTest
@testable import SafeRun

final class ExecutionSafetyTests: XCTestCase {
    private struct Fixture: Sendable {
        let base: URL
        let root: URL
        let engine: SafeExecutionEngine

        init() throws {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("SafeRunSafety-" + UUID().uuidString)
            root = base.appendingPathComponent("Files")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            engine = SafeExecutionEngine(recoveryDirectory: base.appendingPathComponent("Recovery"))
        }
        func clean() { try? FileManager.default.removeItem(at: base) }
        func write(_ name: String, _ content: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(content.utf8).write(to: url)
            return url
        }
        func action(_ type: SafeRunActionType, _ source: String? = nil, _ destination: String? = nil) -> SafeRunAction {
            SafeRunAction(type: type, sourceURL: source.map { root.appendingPathComponent($0) },
                          destinationURL: destination.map { root.appendingPathComponent($0) },
                          filename: destination ?? source ?? "folder", description: type.title, risk: .medium, isReversible: true)
        }
        func plan(_ actions: [SafeRunAction]) -> SafeRunPlan {
            SafeRunPlan(title: "Safety test", originalInstruction: "Test", selectedRootFolder: root,
                        actions: actions, status: .simulationComplete)
        }
        func simulation(_ plan: SafeRunPlan) throws -> SimulationResult {
            SimulationResult(success: true, actionsPassed: plan.actions.count, actionsFailed: 0, conflicts: [], warnings: [],
                             resultingVirtualFilesystem: [], overallRisk: .medium, canExecute: true,
                             snapshot: try FileSnapshot.capture(plan: plan))
        }
        func run(_ plan: SafeRunPlan) async throws -> ExecutionReport {
            try await engine.execute(plan: plan, simulation: simulation(plan), userApproved: true)
        }
        func content(_ name: String) throws -> String { try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }
    }

    func testEveryOperationRoundTripsThroughDurableTransaction() async throws {
        for operation in SafeRunActionType.allCases {
            let f = try Fixture()
            defer { f.clean() }
            _ = try f.write("source", "new")
            if operation == .replaceFile { _ = try f.write("destination", "old") }
            let action = f.action(operation, operation == .createDirectory ? nil : "source", operation == .deleteFile ? nil : "destination")
            let report = try await f.run(f.plan([action]))
            XCTAssertEqual(try f.engine.completedJournals(), [report.journal])
            let restarted = SafeExecutionEngine(recoveryDirectory: f.base.appendingPathComponent("Recovery"))
            try await restarted.rollback(report.journal)
            XCTAssertEqual(try f.content("source"), "new")
            if operation == .replaceFile { XCTAssertEqual(try f.content("destination"), "old") }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("destination").path)) }
            XCTAssertTrue(try restarted.discoverInterruptedTransactions().isEmpty)
            XCTAssertEqual(try restarted.allTransactions().first?.state, .rolledBack)
            try await restarted.rollback(report.journal) // Recovery is idempotent.
        }
    }

    func testSameSizeSameTimestampContentChangeIsRejected() async throws {
        let f = try Fixture(); defer { f.clean() }
        let source = try f.write("source", "aaaa")
        let plan = f.plan([f.action(.moveFile, "source", "destination")])
        let simulation = try f.simulation(plan)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        _ = try f.write("source", "bbbb")
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: source.path)
        do {
            _ = try await f.engine.execute(plan: plan, simulation: simulation, userApproved: true)
            XCTFail("Stale source accepted")
        } catch let error as StalePlanError { XCTAssertEqual(error.changedPaths, [source.path]) }
        XCTAssertEqual(try f.content("source"), "bbbb")
        XCTAssertTrue(try f.engine.allTransactions().isEmpty)
    }

    func testNewDestinationAndMutatedPlanAreRejected() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.write("source", "source")
        let plan = f.plan([f.action(.copyFile, "source", "destination")])
        let simulation = try f.simulation(plan)
        _ = try f.write("destination", "user")
        do { _ = try await f.engine.execute(plan: plan, simulation: simulation, userApproved: true); XCTFail("Collision accepted") }
        catch { XCTAssertTrue(error is StalePlanError) }
        var changed = plan
        changed.actions = [f.action(.deleteFile, "source")]
        do { _ = try await f.engine.execute(plan: changed, simulation: simulation, userApproved: true); XCTFail("Changed plan accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("plan changed")) }
        XCTAssertEqual(try f.content("source"), "source")
        XCTAssertEqual(try f.content("destination"), "user")
    }

    func testRollbackPreservesEditedReplacementAndItsBackup() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.write("source", "new")
        _ = try f.write("destination", "old")
        let report = try await f.run(f.plan([f.action(.replaceFile, "source", "destination")]))
        _ = try f.write("destination", "user edit")
        do { try await f.engine.rollback(report.journal); XCTFail("Changed content removed") } catch {}
        XCTAssertEqual(try f.content("destination"), "user edit")
        let backup = try XCTUnwrap(report.journal.entries.first?.recoveryURL)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "old")
        let interrupted = try XCTUnwrap(f.engine.discoverInterruptedTransactions().first)
        XCTAssertEqual(interrupted.state, .recoveryRequired)
        XCTAssertNotNil(interrupted.entries.first?.failure)
    }

    func testRollbackPreservesNewSourceAndContinuesIndependentUndo() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.write("one", "one")
        _ = try f.write("two", "two")
        let report = try await f.run(f.plan([f.action(.moveFile, "one", "one-moved"), f.action(.deleteFile, "two")]))
        _ = try f.write("two", "new user file")
        do { try await f.engine.rollback(report.journal); XCTFail("Occupied source overwritten") } catch {}
        XCTAssertEqual(try f.content("one"), "one")
        XCTAssertEqual(try f.content("two"), "new user file")
        let tx = try XCTUnwrap(f.engine.discoverInterruptedTransactions().first)
        XCTAssertEqual(tx.entries[0].phase, .undone)
        XCTAssertEqual(try String(contentsOf: tx.entries[1].backupURL, encoding: .utf8), "two")
    }

    func testDirectoryRollbackIsEmptyOnly() async throws {
        let f = try Fixture(); defer { f.clean() }
        let report = try await f.run(f.plan([f.action(.createDirectory, nil, "folder")]))
        _ = try f.write("folder/user", "keep")
        do { try await f.engine.rollback(report.journal); XCTFail("Nonempty directory removed") } catch {}
        XCTAssertEqual(try f.content("folder/user"), "keep")
        XCTAssertEqual(try f.engine.discoverInterruptedTransactions().count, 1)
    }

    func testDirectorySourcesAndSymlinkDestinationsAreRejected() async throws {
        let f = try Fixture(); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.root.appendingPathComponent("directory"), withIntermediateDirectories: false)
        for type in [SafeRunActionType.copyFile, .moveFile, .renameFile, .deleteFile, .replaceFile] {
            let plan = f.plan([f.action(type, "directory", type == .deleteFile ? nil : "destination")])
            do { _ = try await f.run(plan); XCTFail("Directory source accepted") } catch {}
        }
        _ = try f.write("source", "keep")
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("link"), withDestinationURL: f.root.appendingPathComponent("source"))
        XCTAssertThrowsError(try FileSnapshot.capture(plan: f.plan([f.action(.replaceFile, "source", "link")])))
        XCTAssertEqual(try f.content("source"), "keep")
    }

    func testProgressSeesPersistedActionAndLaterFailureRollsBack() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.write("one", "one"); _ = try f.write("two", "two")
        let plan = f.plan([f.action(.moveFile, "one", "one-moved"), f.action(.moveFile, "two", "two-moved")])
        do {
            _ = try await f.engine.execute(plan: plan, simulation: f.simulation(plan), userApproved: true) { progress in
                if progress.completedActions == 1 {
                    let tx = try? f.engine.discoverInterruptedTransactions().first
                    XCTAssertEqual(tx?.entries.first?.phase, .applied)
                    try? Data("external change".utf8).write(to: f.root.appendingPathComponent("two"))
                }
            }
            XCTFail("Stale second action accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("rolled back")) }
        XCTAssertEqual(try f.content("one"), "one")
        XCTAssertEqual(try f.content("two"), "external change")
    }

    func testRestartRecoversCrashBetweenReplacementBackupAndPublish() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.write("source", "new"); _ = try f.write("destination", "old")
        let plan = f.plan([f.action(.replaceFile, "source", "destination")])
        let snapshot = try FileSnapshot.capture(plan: plan)
        let journal = RollbackManager(recoveryDirectory: f.engine.recoveryDirectory).makeJournal(for: plan)
        let storage = f.engine.recoveryDirectory.appendingPathComponent(journal.id.uuidString)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let prefix = storage.appendingPathComponent(plan.actions[0].id.uuidString)
        var entry = ExecutionTransaction.Entry(action: plan.actions[0], sourceBefore: try FileIdentity.read(f.root.appendingPathComponent("source")),
            destinationBefore: try FileIdentity.read(f.root.appendingPathComponent("destination")),
            stagingURL: prefix.appendingPathExtension("stage"), backupURL: prefix.appendingPathExtension("backup"), undoURL: prefix.appendingPathExtension("undo"))
        try FileManager.default.copyItem(at: f.root.appendingPathComponent("source"), to: entry.stagingURL)
        entry.installed = try FileIdentity.read(entry.stagingURL)
        entry.phase = .backingUp
        let tx = ExecutionTransaction(id: journal.id, journal: journal, snapshot: snapshot, entries: [entry])
        try f.engine.transactionStore.save(tx)
        // Simulate termination after the rename but before recording backedUp.
        try FileManager.default.moveItem(at: f.root.appendingPathComponent("destination"), to: entry.backupURL)
        let restarted = SafeExecutionEngine(recoveryDirectory: f.engine.recoveryDirectory)
        XCTAssertEqual(try restarted.discoverInterruptedTransactions().map(\.id), [tx.id])
        try await restarted.recover(tx.id)
        XCTAssertEqual(try f.content("destination"), "old")
        XCTAssertEqual(try f.content("source"), "new")
        try await restarted.recover(tx.id)
    }

    func testRestartRecoversPublishedActionWithoutCompletionRecord() async throws {
        let f = try Fixture(); defer { f.clean() }
        _ = try f.write("source", "source")
        let report = try await f.run(f.plan([f.action(.copyFile, "source", "destination")]))
        var tx = try f.engine.transactionStore.load(report.journal.id)
        tx.state = .executing
        tx.entries[0].phase = .publishing
        try f.engine.transactionStore.save(tx)
        try await SafeExecutionEngine(recoveryDirectory: f.engine.recoveryDirectory).recover(tx.id)
        XCTAssertEqual(try f.content("source"), "source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("destination").path))
    }

    func testCorruptTransactionsAreReportedAndNeverOverwritten() throws {
        let f = try Fixture(); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.engine.transactionStore.directory, withIntermediateDirectories: true)
        let broken = f.engine.transactionStore.directory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("broken".utf8).write(to: broken)
        XCTAssertThrowsError(try f.engine.discoverInterruptedTransactions())
        XCTAssertEqual(try String(contentsOf: broken, encoding: .utf8), "broken")
    }
}
