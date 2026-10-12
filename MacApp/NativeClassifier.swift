import Foundation
import FoundationModels
import CryptoKit
import OSLog

@MainActor
final class NativeClassifier {
    static let shared = NativeClassifier()
    private let logger = Logger(subsystem: "org.mail-filter.app", category: "Classification")
    private let scheduler = InspectionScheduler()
    private var store: SharedStore?

    func inspect(messageID: String?, sender: String, subject: String, recipients: [String], body: DecodedMailBody) async -> Bool {
        let traceID = Self.trace(messageID)
        let settings: NativeSettings
        let store: SharedStore
        do {
            if self.store == nil { self.store = try SharedStore.production() }
            guard let available = self.store else { throw NativeStoreError.unavailable }
            store = available
            settings = try store.settings()
        } catch {
            logger.error("Filtering unavailable; category: privateSettings; no message action applied")
            if let store = self.store { record(store, outcome: "review", category: "privateSettings", traceID: traceID) }
            return false
        }
        guard !settings.paused, let configuration = settings.configuration else {
            record(store, outcome: "skipped", category: settings.paused ? "paused" : "setupRequired", traceID: traceID)
            return false
        }
        let message: MailMessage
        switch configuration.input(messageID: messageID, sender: sender, subject: subject, recipients: recipients, body: body) {
        case .skip(let reason): record(store, outcome: "skipped", category: reason.rawValue, traceID: traceID); return false
        case .classify(let candidate): message = candidate
        }
        do {
            if try store.protects(message.messageID, configuration: configuration) {
                record(store, outcome: "protected", category: "restoredOrPreviouslySelectedForJunk", traceID: traceID)
                return false
            }
        } catch { record(store, outcome: "review", category: "protectionState", traceID: traceID); return false }
        var payloadMessage = message
        payloadMessage.ownAddresses = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(payloadMessage) else {
            record(store, outcome: "review", category: "payloadEncoding", traceID: traceID); return false
        }
        let fingerprint = SHA256.hash(data: Data(settings.revision.utf8) + data).map { String(format: "%02x", $0) }.joined()
        record(store, outcome: "queued", category: "waitingForAnalysis", traceID: traceID)
        var requestJunk = false
        let admission = await scheduler.perform(fingerprint: fingerprint) {
            var attempted = false
            guard let result = await self.generate(message: message, configuration: configuration, store: store,
                                                   onAttempt: { attempted = true }) else {
                // Exhaustion/permanent failure is terminal for this input and
                // settings revision. Duplicate callbacks cannot reset its budget.
                return attempted
            }
            guard !Task.isCancelled else { return false }
            do {
                let outcome = try store.finish(messageID: message.messageID, revision: settings.revision, decision: result.decision, evidence: result.evidence)
                requestJunk = outcome == .junkRequested
                self.record(store, outcome: outcome.rawValue, category: "", processed: true, requested: requestJunk, traceID: traceID, attempt: result.attempt)
                return true
            } catch {
                self.record(store, outcome: "review", category: "protectionWriteOrSettingsChanged", traceID: traceID)
                return false
            }
        }
        switch admission {
        case .completed: return requestJunk
        case .duplicate: record(store, outcome: "skipped", category: "duplicateCallback", traceID: traceID)
        case .queueFull: record(store, outcome: "review", category: "queueFull", traceID: traceID)
        }
        return false
    }

    static func trace(_ messageID: String?) -> String? {
        guard let messageID, let hash = try? JunkIdentity.key(messageID) else { return nil }
        return String(hash.prefix(12))
    }

    func callbackReceived(messageID: String?, hasBody: Bool) {
        if store == nil { store = try? SharedStore.production() }
        if let store {
            record(store, outcome: "callbackReceived", category: hasBody ? "bodyReady" : "bodyRequested",
                   traceID: Self.trace(messageID), callback: true)
        } else { logger.error("Incoming callback could not access private settings") }
    }

    func callbackFailure(_ category: String, messageID: String? = nil) {
        if store == nil { store = try? SharedStore.production() }
        if let store { record(store, outcome: "review", category: category, traceID: Self.trace(messageID)) }
        else { logger.error("Mail callback could not be processed; category: \(category, privacy: .public)") }
    }

    private func generate(message: MailMessage, configuration: FilteringConfiguration, store: SharedStore,
                          onAttempt: @escaping @MainActor () -> Void) async -> (decision: Classification.Decision, evidence: String?, attempt: Int)? {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { record(store, outcome: "review", category: "modelUnavailable", traceID: Self.trace(message.messageID)); return nil }
        let traceID = Self.trace(message.messageID)
        var activeAttempt = 0
        var finalFailureRecorded = false
        do {
            return try await ClassificationRetry.run(
                shouldRetry: { error in
                    if error is AnalysisDeadlineError { return true }
                    if case ClassificationAttemptFailure.generation(let underlying) = error,
                       PoliticalModel.isContextLimit(underlying) { return true }
                    return (error as? ClassificationAttemptFailure)?.retryable ?? false
                },
                onFailure: { attempt, error, retry in
                    guard !Task.isCancelled else { return }
                    let failure = error as? ClassificationAttemptFailure
                    let details = failure?.details ?? (failure == nil ? ModelFailureDetails.describe(error) : nil)
                    self.record(store, outcome: retry ? "retryScheduled" : "review",
                                category: failure?.category ?? details?.category ?? "modelGeneration",
                                traceID: traceID, attempt: attempt, details: details)
                    if !retry { finalFailureRecorded = true }
                },
                operation: { attempt in
                    activeAttempt = attempt
                    onAttempt()
                    self.record(store, outcome: "analysisStarted", category: "onDeviceModel", traceID: traceID, attempt: attempt)
                    // A context failure retries with smaller sections of the
                    // same excerpt, rather than repeating an oversized request.
                    let result: Classification
                    do {
                        result = try await PoliticalModel.classify(message, rules: configuration.rules, model: model,
                            maximumCharacters: 6000 / (1 << (attempt - 1)), onSection: { section, count in
                                self.record(store, outcome: "analysisSection", category: "section\(section)Of\(count)", traceID: traceID, attempt: attempt)
                            }).classification
                    } catch { throw ClassificationAttemptFailure.generation(error) }
                    try Task.checkCancellation()
                    self.record(store, outcome: result.decision == .political ? "modelPolitical" : "modelNotPolitical",
                                category: "", traceID: traceID, attempt: attempt)
                    do {
                        return (result.decision, try validatePoliticalEvidence(result, message: message, terms: configuration.evidenceTerms), attempt)
                    } catch { throw ClassificationAttemptFailure.evidenceRejected }
                })
        } catch {
            if !finalFailureRecorded {
                let details = ModelFailureDetails.describe(error)
                record(store, outcome: "review", category: details.category, traceID: traceID,
                       attempt: activeAttempt > 0 ? activeAttempt : nil, details: details)
            }
            return nil
        }
    }

    private func record(_ store: SharedStore, outcome: String, category: String, processed: Bool = false, requested: Bool = false,
                        traceID: String? = nil, callback: Bool = false, attempt: Int? = nil, details: ModelFailureDetails? = nil) {
        logger.notice("Mail decision: \(outcome, privacy: .public); category: \(category, privacy: .public); key: \(traceID ?? "unavailable", privacy: .public); attempt: \(attempt ?? 0, privacy: .public); error domain: \(details?.domain ?? "", privacy: .public); error code: \(details?.code ?? 0, privacy: .public); Junk action requested: \(requested, privacy: .public)")
        do { try store.record(outcome: outcome, category: category, processed: processed, junkRequested: requested,
                              traceID: traceID, receivedCallback: callback, attempt: attempt,
                              failureDomain: details?.domain, failureCode: details?.code) }
        catch { logger.error("Recent activity could not be saved; category: activityStorage") }
    }
}
