import Foundation
import FoundationModels

struct ModelFailureDetails {
    let category: String
    let retryable: Bool
    let domain: String
    let code: Int

    static func describe(_ error: Error) -> ModelFailureDetails {
        let (category, retryable) = classify(error)
        let failure = error as NSError
        // Never store localized descriptions, context, response text or userInfo.
        let allowed = ["FoundationModels", "com.apple.", "NS", "CF", "Swift.", "AnalysisDeadlineError"]
        let domain = failure.domain
        let safe = domain.count <= 200 && allowed.contains(where: domain.hasPrefix)
            && domain.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        return ModelFailureDetails(category: category, retryable: retryable,
                                   domain: safe ? domain : "other", code: failure.code)
    }

    private static func classify(_ error: Error) -> (String, Bool) {
        if error is AnalysisDeadlineError { return ("modelTimedOut", true) }
        if error is CancellationError { return ("analysisCancelled", false) }
        if let label = error as? ModelLabelError { return label.kind == .refusal ? ("modelRefusal", false) : ("invalidModelResponse", true) }
        if let request = error as? ClassificationRequestError {
            switch request {
            case .instructionsTooLong: return ("promptContextLimit", false)
            case .sectionTooLarge: return ("emailSectionContextLimit", false)
            case .tooManySections: return ("emailSectionLimit", false)
            }
        }
        if #available(macOS 27.0, *) {
            if let failure = error as? LanguageModelError {
                switch failure {
                case .contextSizeExceeded: return ("modelContextLimit", false)
                case .guardrailViolation, .refusal: return ("modelRefusal", false)
                case .unsupportedLanguageOrLocale: return ("modelUnsupportedLanguage", false)
                case .unsupportedGenerationGuide: return ("modelUnsupportedGuide", false)
                case .unsupportedCapability: return ("modelUnsupportedCapability", false)
                case .unsupportedTranscriptContent: return ("modelUnsupportedInput", false)
                case .rateLimited: return ("modelRateLimited", true)
                case .timeout: return ("modelTimedOut", true)
                @unknown default: return ("modelGeneration", true)
                }
            }
            if let failure = error as? LanguageModelSession.Error {
                switch failure {
                case .concurrentRequests: return ("modelConcurrentRequests", true)
                case .transcriptMutationWhileResponding: return ("modelSessionMutation", false)
                @unknown default: return ("modelGeneration", true)
                }
            }
            if error is GeneratedContent.ParsingError { return ("modelDecodingFailure", true) }
            if error is SystemLanguageModel.Error { return ("modelUnavailable", true) }
        }
        if let failure = error as? LanguageModelSession.GenerationError {
            switch failure {
            case .exceededContextWindowSize: return ("modelContextLimit", false)
            case .guardrailViolation, .refusal: return ("modelRefusal", false)
            case .unsupportedLanguageOrLocale: return ("modelUnsupportedLanguage", false)
            case .unsupportedGuide: return ("modelUnsupportedGuide", false)
            case .assetsUnavailable: return ("modelUnavailable", true)
            case .rateLimited: return ("modelRateLimited", true)
            case .concurrentRequests: return ("modelConcurrentRequests", true)
            case .decodingFailure: return ("modelDecodingFailure", true)
            @unknown default: return ("modelGeneration", true)
            }
        }
        return ("modelGeneration", true)
    }
}

enum ClassificationAttemptFailure: Error {
    case generation(Error), invalidResponse, evidenceRejected

    var category: String {
        switch self {
        case .generation(let error): return ModelFailureDetails.describe(error).category
        case .invalidResponse: return "invalidModelResponse"
        case .evidenceRejected: return "evidenceRejected"
        }
    }
    var retryable: Bool {
        switch self {
        case .generation(let error): return ModelFailureDetails.describe(error).retryable
        case .invalidResponse: return true
        case .evidenceRejected: return false
        }
    }
    var details: ModelFailureDetails? {
        if case .generation(let error) = self { return ModelFailureDetails.describe(error) }
        return nil
    }
}

enum ClassificationRetryError: Error { case invalidLimit }

@MainActor
enum ClassificationRetry {
    nonisolated static let maximumAttempts = 3
    nonisolated static let attemptSeconds: TimeInterval = 20
    nonisolated static let totalSeconds: TimeInterval = 60

    static func run<Value>(
        maximumAttempts: Int = maximumAttempts, attemptSeconds: TimeInterval = attemptSeconds,
        totalSeconds: TimeInterval = totalSeconds,
        delay: @escaping @MainActor (Int) async throws -> Void = { attempt in
            try await Task.sleep(for: .seconds(Double(attempt)))
        },
        shouldRetry: @escaping @MainActor (Error) -> Bool,
        onFailure: @escaping @MainActor (Int, Error, Bool) -> Void = { _, _, _ in },
        operation: @escaping @MainActor (Int) async throws -> Value
    ) async throws -> Value {
        guard (1...10).contains(maximumAttempts), attemptSeconds > 0, totalSeconds > 0 else {
            throw ClassificationRetryError.invalidLimit
        }
        return try await AnalysisDeadline.run(seconds: totalSeconds) {
            for attempt in 1...maximumAttempts {
                try Task.checkCancellation()
                do {
                    return try await AnalysisDeadline.run(seconds: attemptSeconds) { try await operation(attempt) }
                } catch {
                    try Task.checkCancellation()
                    let retry = attempt < maximumAttempts && shouldRetry(error)
                    onFailure(attempt, error, retry)
                    guard retry else { throw error }
                    try await delay(attempt)
                }
            }
            throw ClassificationRetryError.invalidLimit
        }
    }
}
