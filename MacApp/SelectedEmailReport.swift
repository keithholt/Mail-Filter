import Foundation

/// An explicit export chosen by the user. Unlike normal application diagnostics,
/// this file contains the selected email so its MIME input can be reproduced.
struct SelectedEmailReport: Encodable {
    struct Policy: Encodable {
        let revision: String
        let paused: Bool
        let mode: String
        let selectedAccount: Bool
        let senderIsOwnAddress: Bool
        let rules: String
        let evidenceTerms: [String]
    }
    let schemaVersion = 1
    let exportedAt = Date()
    let appBuild: String
    let installedExtensionBuild: String?
    let messageID: String
    let diagnosticKey: String?
    let mailID: Int
    let subject: String
    let sender: String
    let sourceBase64: String
    let extractionError: String?
    let extractedBody: String?
    let decodedCharacterCount: Int?
    let excerptTruncated: Bool?
    let currentPolicy: Policy?
    let automaticHistory: [NativeActivity]
    let currentReadOnlyAnalysis: String?

    init(selection: MessageDiagnostics.Selection, settings: NativeSettings, activity: NativeActivityLog,
         analysis: String?, appBuild: String, extensionBuild: String?) {
        let message = selection.message
        self.appBuild = appBuild
        installedExtensionBuild = extensionBuild
        messageID = message.messageID
        let key = (try? JunkIdentity.key(messageID)).map { String($0.prefix(12)) }
        diagnosticKey = key
        mailID = message.id
        subject = message.subject
        sender = message.sender
        sourceBase64 = selection.source.base64EncodedString()
        let decoded = Result { try MIMEBodyDecoder.decode(selection.source) }
        switch decoded {
        case .success(let body):
            extractedBody = body.text
            decodedCharacterCount = body.characterCount
            excerptTruncated = body.truncated
            extractionError = nil
        case .failure(let error):
            extractedBody = nil; decodedCharacterCount = nil; excerptTruncated = nil
            extractionError = (error as? MIMEBodyError)?.rawValue ?? "bodyDecoder"
        }
        if let configuration = settings.configuration {
            var guarded = message
            guarded.ownAddresses = configuration.ownAddresses
            currentPolicy = Policy(revision: settings.revision, paused: settings.paused, mode: configuration.mode,
                selectedAccount: settings.selectedAccountIDs.contains(message.accountID), senderIsOwnAddress: guarded.isFromSelf,
                rules: configuration.rules, evidenceTerms: configuration.evidenceTerms)
        } else { currentPolicy = nil }
        automaticHistory = activity.recent.filter { key != nil && $0.traceID == key }.reversed()
        currentReadOnlyAnalysis = analysis
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
