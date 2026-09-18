import Foundation

enum PlannerModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case luna = "gpt-5.6-luna"
    case terra = "gpt-5.6-terra"
    case sol = "gpt-5.6-sol"

    static let defaultModel: PlannerModel = .terra
    var id: String { rawValue }
    var title: String {
        switch self {
        case .luna: "Luna"
        case .terra: "Terra"
        case .sol: "Sol"
        }
    }
}

enum AIConnectionStatus: Equatable, Sendable {
    /// Model access confirmed; this does not prove generation quota or billing availability.
    case connected(model: PlannerModel)
}

/// Never carries server bodies, request headers, credentials, paths, or underlying errors.
enum AIPlannerError: Error, LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case credentialStorage
    case credentialAlreadyExists
    case unauthorized
    case forbidden
    case modelUnavailable
    case rateLimited
    case serverUnavailable
    case httpStatus(Int)
    case networkUnavailable
    case timedOut
    case invalidResponse
    case responseTooLarge
    case refused
    case incompleteResponse
    case invalidPlan
    case unsafePlan
    case invalidMetadata
    case inputTooLarge
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an OpenAI API key in Settings before generating a plan."
        case .invalidAPIKey: "Enter an API key in the expected format without whitespace."
        case .credentialStorage: "SafeRun could not access the API key in Keychain."
        case .credentialAlreadyExists: "An API key is already saved. Use Replace to update it."
        case .unauthorized: "OpenAI rejected the API key. Check or replace it in Settings."
        case .forbidden: "This API key does not have permission for this request."
        case .modelUnavailable: "The selected model is unavailable to this API key. Choose another model."
        case .rateLimited: "OpenAI's rate or quota limit was reached. Check your account before trying again."
        case .serverUnavailable: "OpenAI is temporarily unavailable. No automatic retry was made."
        case .httpStatus: "OpenAI could not complete the request. No automatic retry was made."
        case .networkUnavailable: "Could not connect to OpenAI. Check your connection before trying again."
        case .timedOut: "The OpenAI request timed out. No automatic retry was made."
        case .invalidResponse: "OpenAI returned an unreadable response. No plan was accepted."
        case .responseTooLarge: "The response exceeded SafeRun's safety limit. No plan was accepted."
        case .refused: "OpenAI declined to generate this plan. Try a different instruction."
        case .incompleteResponse: "OpenAI returned an incomplete response. No plan was accepted."
        case .invalidPlan: "The generated plan did not match SafeRun's required format. No plan was accepted."
        case .unsafePlan: "The generated plan failed local safety validation. No plan was accepted."
        case .invalidMetadata: "Folder metadata includes an unsafe path. Rescan the selected folder."
        case .inputTooLarge: "The instruction or folder metadata exceeds SafeRun's request limit. Narrow the selection."
        case .invalidConfiguration: "The planner's action limit is outside the supported range."
        }
    }
}
