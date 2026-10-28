import Foundation
import FoundationModels
import AppKit

enum MessageDiagnostics {
    struct Selection {
        let message: MailMessage
        let source: Data
        var isEmailFile = false

        func selectedAccount(in settings: NativeSettings) -> Bool {
            if settings.selectedAccountIDs.contains(message.accountID) { return true }
            guard let configuration = settings.configuration, let headers = try? MIMEBodyDecoder.headers(source) else { return false }
            let recipients = ["to", "cc", "delivered-to", "x-original-to"].compactMap { headers[$0] }.joined(separator: ",")
            let addresses = (try? NSRegularExpression(pattern: "[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+"))?.matches(in: recipients, range: NSRange(recipients.startIndex..., in: recipients)) ?? []
            let found = Set(addresses.compactMap { Range($0.range, in: recipients).map { normalizedEmailAddress(String(recipients[$0])) } })
            return !found.isDisjoint(with: configuration.selectedRecipientAddresses.map(normalizedEmailAddress))
        }
    }

    static func emailFile(_ url: URL) throws -> Selection {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 2 * 1_024 * 1_024 else { throw ToolError("Choose an email source file no larger than 2 MiB.") }
        let source = try Data(contentsOf: url)
        let headers = try MIMEBodyDecoder.headers(source)
        let message = MailMessage(accountID: "email-file", account: "Opened email file", id: 0,
            messageID: headers["message-id"] ?? "", subject: try decodedHeader(headers["subject"] ?? ""),
            sender: try decodedHeader(headers["from"] ?? ""), body: "", truncated: false)
        return Selection(message: message, source: source, isEmailFile: true)
    }

    private static func decodedHeader(_ value: String) throws -> String {
        let expression = try NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=")
        var result = value
        for match in expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            let parts = (0...3).map { String(value[Range(match.range(at: $0), in: value)!]) }
            let data: Data
            if parts[2].lowercased() == "b", let decoded = Data(base64Encoded: parts[3]) { data = decoded }
            else if parts[2].lowercased() == "q" {
                let input = Array(parts[3].replacingOccurrences(of: "_", with: " ").utf8)
                var bytes: [UInt8] = []; var index = 0
                while index < input.count {
                    if input[index] == 61 {
                        guard index + 2 < input.count, let byte = UInt8(String(decoding: input[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) else { throw MIMEBodyError.malformedHeaders }
                        bytes.append(byte); index += 3
                    } else { bytes.append(input[index]); index += 1 }
                }
                data = Data(bytes)
            } else { throw MIMEBodyError.malformedHeaders }
            let encoding: String.Encoding
            switch parts[1].lowercased() {
            case "utf-8", "utf8", "us-ascii": encoding = .utf8
            case "iso-8859-1": encoding = .isoLatin1
            case "windows-1252": encoding = .windowsCP1252
            default: throw MIMEBodyError.unsupportedCharset
            }
            guard let text = String(data: data, encoding: encoding), let range = Range(match.range, in: result) else { throw MIMEBodyError.malformedHeaders }
            result.replaceSubrange(range, with: text)
        }
        return result
    }

    static func automaticHistory(messageID: String, activity: NativeActivityLog) -> String {
        guard let key = try? JunkIdentity.key(messageID) else { return "Automatic processing history: message identity unavailable.\n" }
        let trace = String(key.prefix(12))
        let events = activity.recent.filter { $0.traceID == trace }
        guard !events.isEmpty else { return "Automatic processing history: no record retained for this message in recent activity.\n" }
        let date = ISO8601DateFormatter()
        let lines = events.reversed().map { event in
            let attempt = event.attempt.map { " attempt=\($0)" } ?? ""
            let metrics = event.measurementSummary.isEmpty ? "" : " " + event.measurementSummary
            return "\(date.string(from: event.date)) \(event.outcome) \(event.category)\(attempt)\(metrics)"
        }
        return "Original automatic processing history (retained records):\n" + lines.joined(separator: "\n") + "\n\nCurrent read-only analysis follows:\n"
    }

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
            set rawSource to source of msg
            if (count characters of rawSource) > 2097152 then error "This email exceeds the 2 MiB message extraction limit."
            return {acctID, msgID, rfcID, msgSender, msgSubject, rawSource}
        end tell
    end timeout
    """

    @MainActor
    static func selectedMessage() throws -> Selection {
        try MailAccess.requirePermission()
        let row = try MailAutomation.script(selectedMessageScript)
        guard row.numberOfItems == 6, let accountID = row.atIndex(1)?.stringValue,
              let numericID = row.atIndex(2)?.stringValue, let id = Int(numericID) else {
            throw ToolError("Mail did not provide a readable selected message.")
        }
        let message = MailMessage(accountID: accountID, account: "Selected Mail account", id: id,
            messageID: row.atIndex(3)?.stringValue ?? "", subject: row.atIndex(5)?.stringValue ?? "",
            sender: row.atIndex(4)?.stringValue ?? "", body: "", truncated: false)
        return Selection(message: message, source: Data((row.atIndex(6)?.stringValue ?? "").utf8))
    }

    @MainActor
    static func analyze(_ selection: Selection, settings: NativeSettings, activity: NativeActivityLog) async throws -> String {
        guard let configuration = settings.configuration else { throw ToolError("Save filtering settings first.") }
        var message = selection.message
        message.ownAddresses = settings.allowsOwnMailForTesting ? nil : configuration.ownAddresses
        let trace = (try? JunkIdentity.key(message.messageID)).map { String($0.prefix(12)) } ?? "unavailable"
        let prefix = "Read-only test: no messages were moved.\nDiagnostic message key: \(trace)\nSubject: \(message.subject)\n"
            + automaticHistory(messageID: message.messageID, activity: activity)
        guard selection.isEmailFile || selection.selectedAccount(in: settings) else {
            return prefix + "This message belongs to an account that is not selected for filtering."
        }
        if message.isFromSelf { return prefix + message.automaticKeepReason! }
        do {
            // Use the same MIME decoder as incoming processing. Preserve the
            // diagnostic key and original history even if extraction fails.
            let body = try MIMEBodyDecoder.decode(selection.source)
            message.body = body.text
            message.truncated = body.truncated
        } catch {
            return prefix + "Body extraction failed: \((error as? MIMEBodyError)?.rawValue ?? "bodyDecoder"). Model was not invoked."
        }
        if let reason = message.automaticKeepReason { return prefix + reason }
        guard message.canMove || (selection.isEmailFile && message.subject.count <= 500 && message.sender.count <= 500) else { return prefix + "Message identity or headers do not meet the filter's processing requirements." }
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { return prefix + "Apple's on-device model is unavailable." }
        message.ownAddresses = nil
        let response: PoliticalModel.Result
        var requestMeasurements: [String] = []
        do {
            response = try await ClassificationRetry.run(shouldRetry: { error in
                PoliticalModel.isContextLimit(error) || ModelFailureDetails.describe(error).retryable
            }, operation: { attempt in
                try await PoliticalModel.classify(message, rules: configuration.rules, model: model,
                    maximumCharacters: ClassificationRequest.sectionCharacters(forAttempt: attempt), onRequest: { metrics in
                        requestMeasurements.append("attempt=\(attempt) " + metrics.summary)
                    })
            })
        } catch {
            let details = ModelFailureDetails.describe(error)
            let reply = (error as? ModelLabelError).map { "\n" + $0.diagnosticReply } ?? ""
            return prefix + "Classification failed: \(details.category)\nError: \(details.domain) (\(details.code))\n\(error.localizedDescription)" + reply
                + "\nRequest measurements:\n" + requestMeasurements.joined(separator: "\n")
                + "\nAnalyzed MIME body excerpt (shown only here):\n\(message.body)"
        }
        let result = response.classification
        let decision = result.decision == .political ? "political" : "not-political"
        var text = prefix + (selection.isEmailFile ? "Email file analysis only. Account matching uses visible recipient headers and may be incomplete for aliases or Bcc. Selected recipient matched: \(selection.selectedAccount(in: settings)).\n" : "")
            + "Model decision: \(decision)\nReason: \(result.reason)\nMIME excerpt: \(message.body.count) characters; model sections: \(response.sections)"
        do {
            let evidence = try validatePoliticalEvidence(result, message: message, terms: configuration.evidenceTerms)
            if configuration.evidenceTerms.isEmpty { text += "\nKeyword validation: disabled (empty list)." }
            if let evidence { text += "\nVerified political evidence: \(evidence)" }
        } catch {
            text += "\nThe model's positive did not pass evidence verification. Normal filtering would leave it in Inbox."
        }
        if message.truncated { text += "\nOnly the first 6,000 body characters were analyzed." }
        text += "\nRequest measurements:\n" + requestMeasurements.joined(separator: "\n")
        if result.decision == .notPolitical { text += "\nAnalyzed MIME body excerpt (shown only here):\n\(message.body)" }
        return text
    }
}
