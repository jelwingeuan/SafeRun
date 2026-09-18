import Foundation
import XCTest
@testable import SafeRun

final class AIPlannerSafetyTests: XCTestCase {
    func testStructuredPlanDecodesOnlySupportedRelativeActions() throws {
        let planID = UUID()
        let actionID = UUID()
        let object: [String: Any] = [
            "id": planID.uuidString,
            "title": "Move receipt",
            "userIntent": "Move the receipt into Receipts.",
            "rootDirectory": ".",
            "actions": [[
                "id": actionID.uuidString,
                "actionType": "moveFile",
                "sourcePath": "receipt.pdf",
                "destinationPath": "Receipts/receipt.pdf",
                "explanation": "Place the receipt in the requested folder.",
                "confidence": 0.9,
                "proposedRisk": "low",
                "reversible": true
            ]],
            "warnings": [],
            "rationale": "The source file is present in the supplied metadata.",
            "estimatedRisk": "low"
        ]

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try AIPlanDTO.decode(data, maximumActions: 10)

        XCTAssertEqual(decoded.id, planID)
        XCTAssertEqual(decoded.actions.map(\.id), [actionID])
        XCTAssertEqual(decoded.actions.first?.sourcePath, "receipt.pdf")
    }

    func testStructuredPlanRejectsPathTraversalBeforeAnyExecution() throws {
        let object: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Unsafe move",
            "userIntent": "Move a file.",
            "rootDirectory": ".",
            "actions": [[
                "id": UUID().uuidString,
                "actionType": "moveFile",
                "sourcePath": "receipt.pdf",
                "destinationPath": "../outside.pdf",
                "explanation": "Unsafe destination.",
                "confidence": 1.0,
                "proposedRisk": "low",
                "reversible": true
            ]],
            "warnings": [],
            "rationale": "Unsafe.",
            "estimatedRisk": "low"
        ]

        XCTAssertThrowsError(try AIPlanDTO.decode(JSONSerialization.data(withJSONObject: object), maximumActions: 10)) { error in
            XCTAssertEqual(error as? AIPlannerError, .invalidPlan)
        }
    }

    func testPlannerMetadataKeepsAbsoluteFolderLocationOutOfRequest() throws {
        let root = URL(fileURLWithPath: "/private/tmp/SafeRun Private Folder", isDirectory: true)
        let visibleURL = root.appendingPathComponent("invoice.pdf")
        let hiddenURL = root.appendingPathComponent("shortcut")
        let context = FolderContext(
            rootFolder: root,
            entries: [
                FolderEntry(url: visibleURL, relativePath: "invoice.pdf", name: "invoice.pdf", fileExtension: "pdf", byteSize: 42, createdAt: nil, modifiedAt: nil, isDirectory: false, isSymbolicLink: false),
                FolderEntry(url: hiddenURL, relativePath: "shortcut", name: "shortcut", fileExtension: "", byteSize: 0, createdAt: nil, modifiedAt: nil, isDirectory: false, isSymbolicLink: true)
            ],
            generatedAt: .now
        )

        let request = try PlannerMetadata(instruction: "Organize \(root.path)", context: context).jsonString()

        XCTAssertFalse(request.contains(root.path))
        XCTAssertTrue(request.contains("invoice.pdf"))
        XCTAssertFalse(request.contains("shortcut"))
    }
}
