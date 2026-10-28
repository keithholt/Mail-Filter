import Foundation
import FoundationModels

struct RetryCheckFailure: Error { let name: String }

@main
@MainActor
struct RetryChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw RetryCheckFailure(name: name) }
        count += 1
    }
    static func retryable(_ error: Error) -> Bool {
        error is AnalysisDeadlineError || (error as? ClassificationAttemptFailure)?.retryable == true
    }
    static func main() async throws {
        let empty = ModelLabelError(kind: .emptyResponse, response: "")
        let malformed = ModelLabelError(kind: .invalidLabel, response: "private-model-response")
        try check(ModelFailureDetails.describe(empty).category == "modelEmptyResponse" && ModelFailureDetails.describe(empty).retryable,
                  "empty replies are distinctly diagnosed and remain retryable")
        try check(ModelFailureDetails.describe(malformed).category == "invalidModelResponse" && !ModelFailureDetails.describe(malformed).domain.contains("private"),
                  "malformed labels remain distinct without exposing the reply")
        var attempts = 0
        let first = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable) { _ in
            attempts += 1; return 42
        }
        try check(first == 42 && attempts == 1, "success never repeats")

        attempts = 0
        var delays: [Int] = [], failures: [Int] = []
        let recovered = try await ClassificationRetry.run(delay: { delays.append($0) }, shouldRetry: retryable,
            onFailure: { attempt, _, retry in if retry { failures.append(attempt) } }) { attempt in
                attempts += 1
                if attempt < 3 { throw ClassificationAttemptFailure.generation(NSError(domain: "FoundationModels.Test", code: 1008)) }
                return 99
            }
        try check(recovered == 99 && attempts == 3 && failures == [1, 2] && delays == [1, 2],
                  "temporary generation failures receive two bounded retries")

        attempts = 0
        var retryFlags: [Bool] = []
        do {
            let _: Int = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable,
                onFailure: { _, _, retry in retryFlags.append(retry) }) { _ in
                    attempts += 1; throw ClassificationAttemptFailure.invalidResponse
                }
            throw RetryCheckFailure(name: "exhausted errors must propagate")
        } catch ClassificationAttemptFailure.invalidResponse { }
        try check(attempts == 3 && retryFlags == [true, true, false], "exhaustion stops at three total attempts")

        attempts = 0
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "private-body-marker")
        let unsupported = ClassificationAttemptFailure.generation(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context))
        do {
            let _: Int = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable) { _ in
                attempts += 1; throw unsupported
            }
        } catch { }
        try check(attempts == 1 && unsupported.category == "modelUnsupportedLanguage", "unsupported language is diagnosed without futile retries")
        attempts = 0
        do {
            let _: Int = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable) { _ in
                attempts += 1; throw ClassificationAttemptFailure.evidenceRejected
            }
        } catch { }
        try check(attempts == 1, "evidence rejection is never retried to force a positive")

        attempts = 0
        let negative = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable) { _ in
            attempts += 1
            return try parseClassification("{\"decision\":\"not-political\",\"reason\":\"Charitable donation\",\"evidence\":\"\"}")
        }
        let message = MailMessage(accountID: "example", account: "Example", id: 1, messageID: "id@example.org",
            subject: "Donation match", sender: "external@example.org", body: "Support the MAGA movement.", truncated: false)
        try check(negative.decision == .notPolitical && attempts == 1
                  && (try validatePoliticalEvidence(negative, message: message, terms: PoliticalVerificationWords.additions)) == nil,
                  "valid negative remains final even with newly added verification words")

        attempts = 0
        let positive = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable) { attempt in
            attempts += 1
            let text = attempt == 1 ? "not JSON" : "{\"decision\":\"political\",\"reason\":\"Political solicitation\",\"evidence\":\"Support the MAGA movement.\"}"
            do { return try parseClassification(text) }
            catch { throw ClassificationAttemptFailure.invalidResponse }
        }
        try check(attempts == 2 && (try validatePoliticalEvidence(positive, message: message, terms: PoliticalVerificationWords.additions)) == message.body,
                  "invalid response can recover to a verified MAGA positive")

        var hung: CheckedContinuation<Int, Never>?
        var lateAction = false
        let timedRecovery = try await ClassificationRetry.run(attemptSeconds: 0.025, totalSeconds: 1,
            delay: { _ in }, shouldRetry: retryable) { attempt in
                if attempt == 1 {
                    let value = await withCheckedContinuation { hung = $0 }
                    try Task.checkCancellation()
                    lateAction = true
                    return value
                }
                return 7
            }
        try check(timedRecovery == 7 && hung != nil, "an uncooperative attempt times out and a later attempt can succeed")
        hung?.resume(returning: 100)
        for _ in 0..<20 { await Task.yield() }
        try check(!lateAction, "late timed-out generation cannot reach a message action")

        attempts = 0
        let began = ProcessInfo.processInfo.systemUptime
        do {
            let _: Int = try await ClassificationRetry.run(attemptSeconds: 1, totalSeconds: 0.04,
                delay: { _ in try await Task.sleep(for: .milliseconds(30)) }, shouldRetry: retryable) { _ in
                    attempts += 1; throw ClassificationAttemptFailure.invalidResponse
                }
        } catch is AnalysisDeadlineError { }
        try check(attempts < 3 && ProcessInfo.processInfo.systemUptime - began < 1, "retries share one overall deadline including backoff")

        var blockedDelay: CheckedContinuation<Void, Never>?
        attempts = 0
        let cancelled = Task { @MainActor in
            do {
                let _: Int = try await ClassificationRetry.run(delay: { _ in await withCheckedContinuation { blockedDelay = $0 } },
                    shouldRetry: retryable) { _ in attempts += 1; throw ClassificationAttemptFailure.invalidResponse }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        while blockedDelay == nil { await Task.yield() }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        try check(cancelledResult, "parent cancellation returns during retry backoff")
        blockedDelay?.resume()
        for _ in 0..<20 { await Task.yield() }
        try check(attempts == 1, "cancellation prevents a later attempt")

        let scheduler = InspectionScheduler()
        _ = await scheduler.perform(fingerprint: "failed") {
            do {
                let _: Int = try await ClassificationRetry.run(delay: { _ in }, shouldRetry: retryable) { _ in
                    throw ClassificationAttemptFailure.invalidResponse
                }
            } catch { }
            return true // Terminal exhaustion is complete, although no move is requested.
        }
        var nextRan = false
        _ = await scheduler.perform(fingerprint: "next") { nextRan = true; return true }
        try check(nextRan && scheduler.pendingCount == 0, "retry exhaustion releases the queue for later messages")
        var duplicateRan = false
        _ = await scheduler.perform(fingerprint: "failed") { duplicateRan = true; return true }
        try check(!duplicateRan, "duplicate callbacks cannot reset a terminally exhausted retry budget")

        let decoding = ModelFailureDetails.describe(LanguageModelSession.GenerationError.decodingFailure(context))
        let overlapping = ModelFailureDetails.describe(LanguageModelSession.GenerationError.concurrentRequests(context))
        try check(decoding.category == "modelDecodingFailure" && overlapping.category == "modelConcurrentRequests"
                  && decoding.retryable && overlapping.retryable, "previously generic errors receive specific categories")
        let guide = ModelFailureDetails.describe(LanguageModelSession.GenerationError.unsupportedGuide(context))
        try check(!guide.retryable && guide.category == "modelUnsupportedGuide", "permanent guide failure is not retried")
        let detail = ModelFailureDetails.describe(NSError(domain: "FoundationModels.Test", code: 1008,
            userInfo: [NSLocalizedDescriptionKey: "private-body-marker"]))
        try check(detail.domain == "FoundationModels.Test" && detail.code == 1008
                  && !"\(detail.category) \(detail.domain) \(detail.code)".contains("private-body-marker"),
                  "failure metadata excludes email-bearing descriptions and userInfo")
        let privateDomain = ModelFailureDetails.describe(NSError(domain: "private-address@example.org", code: 1))
        try check(privateDomain.domain == "other", "unrecognized or email-bearing error domains are not published")
        if #available(macOS 27.0, *) {
            let permanent: [(Error, String)] = [
                (LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: .init("xx"), debugDescription: "private-body-marker")), "modelUnsupportedLanguage"),
                (LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 8000, debugDescription: "private-body-marker")), "modelContextLimit"),
                (LanguageModelError.guardrailViolation(.init(debugDescription: "private-body-marker")), "modelRefusal"),
                (LanguageModelError.refusal(.init(explanation: "private-body-marker", debugDescription: "private-body-marker")), "modelRefusal"),
                (LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil, debugDescription: "private-body-marker")), "modelUnsupportedGuide"),
                (LanguageModelError.unsupportedTranscriptContent(.init(unsupportedContent: [], debugDescription: "private-body-marker")), "modelUnsupportedInput"),
                (LanguageModelSession.Error.transcriptMutationWhileResponding, "modelSessionMutation")
            ]
            for (error, category) in permanent {
                let result = ModelFailureDetails.describe(error)
                try check(result.category == category && !result.retryable, "macOS 27 permanent \(category) does not become a generic retryable failure")
            }
            let temporary: [(Error, String)] = [
                (LanguageModelError.timeout(.init(debugDescription: "private-body-marker")), "modelTimedOut"),
                (LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "private-body-marker")), "modelRateLimited"),
                (LanguageModelSession.Error.concurrentRequests, "modelConcurrentRequests"),
                (GeneratedContent.ParsingError(rawContent: "private-body-marker", debugDescription: "private-body-marker"), "modelDecodingFailure"),
                (SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "private-body-marker")), "modelUnavailable")
            ]
            for (error, category) in temporary {
                let result = ModelFailureDetails.describe(error)
                try check(result.category == category && result.retryable && !result.domain.contains("private-body-marker"),
                          "macOS 27 temporary \(category) is identified without logging its content")
            }
        }
        do {
            let _: Int = try await ClassificationRetry.run(maximumAttempts: 0, shouldRetry: retryable) { _ in 1 }
            throw RetryCheckFailure(name: "invalid limit accepted")
        } catch is ClassificationRetryError { }
        try check(true, "invalid retry limit is rejected")
        print("Passed \(count) retry, exhaustion, cancellation, deadline, evidence and error-privacy checks; no model or Mail calls")
    }
}
