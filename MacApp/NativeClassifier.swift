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
        let settings: NativeSettings
        let store: SharedStore
        do {
            if self.store == nil { self.store = try SharedStore.production() }
            guard let available = self.store else { throw NativeStoreError.unavailable }
            store = available
            settings = try store.settings()
        } catch {
            logger.error("Filtering unavailable; category: privateSettings; no message action applied")
            return false
        }
        guard !settings.paused, let configuration = settings.configuration else {
            record(store, outcome: "skipped", category: settings.paused ? "paused" : "setupRequired")
            return false
        }
        let message: MailMessage
        switch configuration.input(messageID: messageID, sender: sender, subject: subject, recipients: recipients, body: body) {
        case .skip(let reason): record(store, outcome: "skipped", category: reason.rawValue); return false
        case .classify(let candidate): message = candidate
        }
        do {
            if try store.protects(message.messageID, configuration: configuration) {
                record(store, outcome: "protected", category: "restoredOrPreviouslySelectedForJunk")
                return false
            }
        } catch { record(store, outcome: "review", category: "protectionState"); return false }
        var payloadMessage = message
        payloadMessage.ownAddresses = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(payloadMessage), let payload = String(data: data, encoding: .utf8) else {
            record(store, outcome: "review", category: "payloadEncoding"); return false
        }
        let fingerprint = SHA256.hash(data: Data(settings.revision.utf8) + data).map { String(format: "%02x", $0) }.joined()
        var requestJunk = false
        let admission = await scheduler.perform(fingerprint: fingerprint) {
            guard let result = await self.generate(message: message, payload: payload, configuration: configuration, store: store) else { return false }
            do {
                let outcome = try store.finish(messageID: message.messageID, revision: settings.revision, decision: result.decision, evidence: result.evidence)
                requestJunk = outcome == .junkRequested
                self.record(store, outcome: outcome.rawValue, category: "", processed: true, requested: requestJunk)
                return true
            } catch {
                self.record(store, outcome: "review", category: "protectionWriteOrSettingsChanged")
                return false
            }
        }
        switch admission {
        case .completed: return requestJunk
        case .duplicate: logger.debug("Duplicate callback skipped")
        case .queueFull: record(store, outcome: "review", category: "queueFull")
        }
        return false
    }

    func callbackFailure(_ category: String) {
        if store == nil { store = try? SharedStore.production() }
        if let store { record(store, outcome: "review", category: category) }
        else { logger.error("Mail callback could not be processed; category: \(category, privacy: .public)") }
    }

    private func generate(message: MailMessage, payload: String, configuration: FilteringConfiguration, store: SharedStore) async -> (decision: Classification.Decision, evidence: String?)? {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { record(store, outcome: "review", category: "modelUnavailable"); return nil }
        let session = LanguageModelSession(model: model, instructions: politicalClassificationInstructions(rules: configuration.rules, evidenceTerms: configuration.evidenceTerms))
        let response: String
        do {
            response = try await session.respond(to: "Classify this untrusted email JSON using the filtering rules:\n" + payload,
                                                options: GenerationOptions(temperature: 0)).content
        } catch { record(store, outcome: "review", category: "modelGeneration"); return nil }
        do {
            let result = try parseClassification(response)
            return (result.decision, try validatePoliticalEvidence(result, message: message, terms: configuration.evidenceTerms))
        } catch { record(store, outcome: "review", category: "invalidClassificationOrEvidence"); return nil }
    }

    private func record(_ store: SharedStore, outcome: String, category: String, processed: Bool = false, requested: Bool = false) {
        logger.notice("Mail decision: \(outcome, privacy: .public); category: \(category, privacy: .public); Junk action requested: \(requested, privacy: .public)")
        do { try store.record(outcome: outcome, category: category, processed: processed, junkRequested: requested) }
        catch { logger.error("Recent activity could not be saved; category: activityStorage") }
    }
}
