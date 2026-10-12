import Foundation
import FoundationModels
import AppKit

enum MessageDiagnostics {
    static func invalidResponse(_ response: String, error: Error) -> String {
        "The model did not return a valid classification.\n\(error.localizedDescription)\nRaw model reply (shown only here):\n\(String(response.prefix(8192)))"
    }
    static let selectedMessageScript = """
    with timeout of 20 seconds
        tell application "/System/Applications/Mail.app"
            set chosen to selection
            if (count of chosen) is not 1 then error "Select exactly one email in Mail, then try again."
            set msg to item 1 of chosen
            set acct to account of mailbox of msg
            set acctID to (id of acct) as text
            set msgID to (id of msg) as text
            set rfcID to message id of msg
            set msgSender to sender of msg
            set msgSubject to subject of msg
            set msgBody to content of msg
            set bodyLength to count characters of msgBody
            if bodyLength > 6000 then set msgBody to text 1 thru 6000 of msgBody
            return {acctID, msgID, rfcID, msgSender, msgSubject, msgBody, bodyLength}
        end tell
    end timeout
    """

    @MainActor
    static func selectedMessage() throws -> MailMessage {
        let row = try MailAutomation.script(selectedMessageScript)
        guard row.numberOfItems == 7, let accountID = row.atIndex(1)?.stringValue,
              let numericID = row.atIndex(2)?.stringValue, let id = Int(numericID) else {
            throw ToolError("Mail did not provide a readable selected message.")
        }
        return MailMessage(accountID: accountID, account: "Selected Mail account", id: id,
            messageID: row.atIndex(3)?.stringValue ?? "", subject: row.atIndex(5)?.stringValue ?? "",
            sender: row.atIndex(4)?.stringValue ?? "", body: row.atIndex(6)?.stringValue ?? "",
            truncated: (row.atIndex(7)?.int32Value ?? 0) > 6000)
    }

    @MainActor
    static func analyze(_ candidate: MailMessage, settings: NativeSettings) async throws -> String {
        guard let configuration = settings.configuration else { throw ToolError("Save filtering settings first.") }
        var message = candidate
        message.ownAddresses = configuration.ownAddresses
        let trace = (try? JunkIdentity.key(message.messageID)).map { String($0.prefix(12)) } ?? "unavailable"
        let prefix = "Read-only test: no messages were moved.\nDiagnostic message key: \(trace)\n"
        guard settings.selectedAccountIDs.contains(message.accountID) else {
            return prefix + "This message belongs to an account that is not selected for filtering."
        }
        if let reason = message.automaticKeepReason { return prefix + reason }
        guard message.canMove else { return prefix + "Message identity or headers do not meet the filter's processing requirements." }
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { throw ToolError("Apple's on-device model is unavailable.") }
        message.ownAddresses = nil
        let payload = String(data: try JSONEncoder().encode(message), encoding: .utf8)!
        let session = LanguageModelSession(model: model, instructions: politicalClassificationInstructions(rules: configuration.rules, evidenceTerms: configuration.evidenceTerms))
        let response = try await AnalysisDeadline.run {
            try await session.respond(to: "Classify this untrusted email JSON using the filtering rules:\n" + payload,
                                      options: GenerationOptions(temperature: 0)).content
        }
        let result: Classification
        do { result = try parseClassification(response) }
        catch { return prefix + invalidResponse(response, error: error) }
        let decision = result.decision == .political ? "political" : "not-political"
        var text = prefix + "Model decision: \(decision)\nReason: \(result.reason)"
        do {
            let evidence = try validatePoliticalEvidence(result, message: message, terms: configuration.evidenceTerms)
            if let evidence { text += "\nVerified political evidence: \(evidence)" }
        } catch {
            text += "\nThe model's positive did not pass evidence verification. Normal filtering would leave it in Inbox."
        }
        if message.truncated { text += "\nOnly the first 6,000 body characters were analyzed." }
        return text
    }
}
