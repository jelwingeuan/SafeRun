import Foundation

enum AIRisk: String, Codable, CaseIterable, Sendable {
    case low, medium, high, critical

    var riskLevel: RiskLevel {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .critical: .critical
        }
    }
}

struct AIPlanDTO: Decodable, Sendable {
    let id: UUID
    let title: String
    let userIntent: String
    let rootDirectory: String
    let actions: [Action]
    let warnings: [String]
    let rationale: String
    let estimatedRisk: AIRisk

    struct Action: Decodable, Sendable {
        let id: UUID
        let actionType: SafeRunActionType
        let sourcePath: String?
        let destinationPath: String?
        let explanation: String
        let confidence: Double
        let proposedRisk: AIRisk
        let reversible: Bool
    }

    static let planKeys: Set<String> = [
        "id", "title", "userIntent", "rootDirectory", "actions", "warnings", "rationale", "estimatedRisk"
    ]
    static let actionKeys: Set<String> = [
        "id", "actionType", "sourcePath", "destinationPath", "explanation", "confidence", "proposedRisk", "reversible"
    ]

    static func decode(_ data: Data, maximumActions: Int) throws -> AIPlanDTO {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == planKeys,
                  let actions = object["actions"] as? [[String: Any]],
                  actions.count <= maximumActions,
                  actions.allSatisfy({ Set($0.keys) == actionKeys }) else {
                throw AIPlannerError.invalidPlan
            }
            let plan = try JSONDecoder().decode(Self.self, from: data)
            guard plan.rootDirectory == ".",
                  validText(plan.title, maximum: 200),
                  validText(plan.userIntent, maximum: 8_000),
                  validText(plan.rationale, maximum: 4_000),
                  plan.warnings.count <= 50,
                  plan.warnings.allSatisfy({ validText($0, maximum: 1_000) }),
                  Set(plan.actions.map(\.id)).count == plan.actions.count else {
                throw AIPlannerError.invalidPlan
            }
            for action in plan.actions {
                guard validText(action.explanation, maximum: 2_000),
                      action.confidence.isFinite, (0...1).contains(action.confidence),
                      action.sourcePath.map(isRelativePath) ?? true,
                      action.destinationPath.map(isRelativePath) ?? true else {
                    throw AIPlannerError.invalidPlan
                }
                switch action.actionType {
                case .createDirectory:
                    guard action.sourcePath == nil, action.destinationPath != nil else {
                        throw AIPlannerError.invalidPlan
                    }
                case .deleteFile:
                    guard action.sourcePath != nil, action.destinationPath == nil else {
                        throw AIPlannerError.invalidPlan
                    }
                case .moveFile, .copyFile, .renameFile, .replaceFile:
                    guard let source = action.sourcePath, let destination = action.destinationPath,
                          source != destination else { throw AIPlannerError.invalidPlan }
                }
            }
            return plan
        } catch {
            throw AIPlannerError.invalidPlan
        }
    }

    static func isRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 1_024,
              !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func validText(_ text: String, maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= maximum
            && !text.contains("\0")
    }

    static func schema(maximumActions: Int) -> [String: Any] {
        func string(_ maximum: Int) -> [String: Any] {
            ["type": "string", "minLength": 1, "maxLength": maximum]
        }
        let risk: [String: Any] = ["type": "string", "enum": AIRisk.allCases.map(\.rawValue)]
        let path: [String: Any] = ["type": ["string", "null"], "minLength": 1, "maxLength": 1_024]
        let uuid: [String: Any] = ["type": "string", "format": "uuid"]
        return [
            "type": "object", "additionalProperties": false, "required": planKeys.sorted(),
            "properties": [
                "id": uuid, "title": string(200), "userIntent": string(8_000),
                "rootDirectory": ["type": "string", "enum": ["."]],
                "actions": [
                    "type": "array", "maxItems": maximumActions,
                    "items": [
                        "type": "object", "additionalProperties": false, "required": actionKeys.sorted(),
                        "properties": [
                            "id": uuid,
                            "actionType": ["type": "string", "enum": SafeRunActionType.allCases.map(\.rawValue)],
                            "sourcePath": path, "destinationPath": path,
                            "explanation": string(2_000),
                            "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                            "proposedRisk": risk, "reversible": ["type": "boolean"]
                        ]
                    ]
                ],
                "warnings": ["type": "array", "maxItems": 50, "items": string(1_000)],
                "rationale": string(4_000), "estimatedRisk": risk
            ]
        ]
    }

    func makePlan(context: FolderContext, instruction: String) -> SafeRunPlan {
        let root = context.rootFolder
        let mappedActions = actions.map { action in
            SafeRunAction(
                id: action.id, type: action.actionType,
                sourceURL: action.sourcePath.map { root.appendingPathComponent($0) },
                destinationURL: action.destinationPath.map { root.appendingPathComponent($0) },
                filename: ((action.sourcePath ?? action.destinationPath ?? "") as NSString).lastPathComponent,
                description: action.explanation, risk: action.proposedRisk.riskLevel,
                isReversible: action.reversible,
                confidence: action.confidence, proposedRisk: action.proposedRisk.riskLevel
            )
        }
        return SafeRunPlan(
            id: id, title: title, originalInstruction: instruction, selectedRootFolder: root,
            actions: mappedActions, warnings: warnings, status: .ready,
            rationale: rationale, estimatedRisk: estimatedRisk.riskLevel
        )
    }
}
