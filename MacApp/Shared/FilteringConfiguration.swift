import Foundation

enum FilteringConfigurationError: String, Error {
    case invalidConfiguration, accountSelectionMismatch, missingAddresses, unreadableConfiguration, unreadableProtection
}

enum FilteringSkipReason: String {
    case selfMail, emptyBody, recipientNotSelected, missingIdentity, oversizedHeaders
}

enum FilteringInput {
    case classify(MailMessage)
    case skip(FilteringSkipReason)
}

struct FilteringAccount {
    let id: String
    let name: String
    let addresses: [String]
}

/// Saved filtering policy. The wire format also accepts earlier configuration snapshots.
/// Apply is the default; preview is explicit.
struct FilteringConfiguration: Codable {
    let schemaVersion: Int
    let mode: String
    let selectedRecipientAddresses: [String]
    let ownAddresses: [String]
    let rules: String
    let evidenceTerms: [String]
    let legacyAccountIDs: [String]
    let protectedCLIIdentities: [String]

    func validate() throws {
        guard schemaVersion == 2, ["apply", "dry-run"].contains(mode), !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              rules.count <= 32_000, evidenceTerms.count <= 512,
              evidenceTerms.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }),
              !selectedRecipientAddresses.isEmpty, !ownAddresses.isEmpty, ownAddresses.count <= 1_024,
              selectedRecipientAddresses.count <= 1_024, !legacyAccountIDs.isEmpty, legacyAccountIDs.count <= 1_024,
              legacyAccountIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 256 }),
              protectedCLIIdentities.count <= 2_048, protectedCLIIdentities.allSatisfy(JunkIdentity.isDigest) else {
            throw FilteringConfigurationError.invalidConfiguration
        }
        let own = Set(ownAddresses.map(normalizedEmailAddress))
        let selected = Set(selectedRecipientAddresses.map(normalizedEmailAddress))
        guard selected.isSubset(of: own), own.allSatisfy({ $0.contains("@") && !$0.contains(where: { $0.isWhitespace }) && $0.count <= 320 }) else {
            throw FilteringConfigurationError.invalidConfiguration
        }
    }

    static func make(selectedNames: [String], inventory: [FilteringAccount], rules: String, evidenceTerms: [String],
                     mode: String = "apply", protectedCLIIdentities: [String] = []) throws -> FilteringConfiguration {
        guard !selectedNames.isEmpty else { throw FilteringConfigurationError.accountSelectionMismatch }
        var selected: [String] = []
        for name in selectedNames {
            let matches = inventory.filter { $0.name == name }
            guard matches.count == 1 else { throw FilteringConfigurationError.accountSelectionMismatch }
            guard !matches[0].addresses.isEmpty else { throw FilteringConfigurationError.missingAddresses }
            selected += matches[0].addresses
        }
        let result = FilteringConfiguration(schemaVersion: 2, mode: mode,
            selectedRecipientAddresses: Array(Set(selected.map(normalizedEmailAddress))).sorted(),
            ownAddresses: Array(Set(inventory.flatMap(\.addresses).map(normalizedEmailAddress))).sorted(),
            rules: rules, evidenceTerms: evidenceTerms,
            legacyAccountIDs: Array(Set(inventory.map(\.id))).sorted(), protectedCLIIdentities: Array(Set(protectedCLIIdentities)).sorted())
        try result.validate()
        return result
    }

    static func cliProtection(_ url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 16 * 1_024 * 1_024 else { throw FilteringConfigurationError.unreadableProtection }
            let data = try Data(contentsOf: url)
            guard data.count <= 16 * 1_024 * 1_024 else { throw FilteringConfigurationError.unreadableProtection }
            // Older CLI arrays contain kept fingerprints only, not move protection.
            if let legacy = try? JSONDecoder().decode([String].self, from: data), legacy.allSatisfy(JunkIdentity.isDigest) { return [] }
            struct Saved: Decodable { let kept: [String]; let junk: [String] }
            let saved = try JSONDecoder().decode(Saved.self, from: data)
            guard saved.junk.count <= 2_048, saved.junk.allSatisfy(JunkIdentity.isDigest) else { throw FilteringConfigurationError.unreadableProtection }
            return Array(Set(saved.junk)).sorted()
        } catch { throw FilteringConfigurationError.unreadableProtection }
    }

    static func load(_ url: URL) throws -> FilteringConfiguration {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 256 * 1_024 else { throw FilteringConfigurationError.unreadableConfiguration }
        let data = try Data(contentsOf: url)
        guard data.count <= 256 * 1_024 else { throw FilteringConfigurationError.unreadableConfiguration }
        let configuration = try JSONDecoder().decode(FilteringConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }

    func input(messageID: String?, sender: String, subject: String, recipients: [String], body: DecodedMailBody) -> FilteringInput {
        evaluate(messageID: messageID, sender: sender, subject: subject, recipients: recipients, body: body, protectSelf: true)
    }

    #if MAIL_FILTER_DEV
    func developmentInput(messageID: String?, sender: String, subject: String, recipients: [String], body: DecodedMailBody,
                          allowOwnMail: Bool) -> FilteringInput {
        evaluate(messageID: messageID, sender: sender, subject: subject, recipients: recipients, body: body, protectSelf: !allowOwnMail)
    }
    #endif

    private func evaluate(messageID: String?, sender: String, subject: String, recipients: [String], body: DecodedMailBody,
                          protectSelf: Bool) -> FilteringInput {
        let message = MailMessage(accountID: "mailkit", account: "MailKit", id: 0,
            messageID: messageID ?? "", subject: subject, sender: sender,
            body: body.text, truncated: body.truncated, ownAddresses: ownAddresses)
        if protectSelf && message.isFromSelf { return .skip(.selfMail) }
        let selected = Set(selectedRecipientAddresses.map(normalizedEmailAddress))
        guard recipients.contains(where: { selected.contains(normalizedEmailAddress($0)) }) else { return .skip(.recipientNotSelected) }
        if !message.hasMeaningfulBody { return .skip(.emptyBody) }
        guard !message.messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .skip(.missingIdentity) }
        guard (try? JunkIdentity.canonical(message.messageID)) != nil else { return .skip(.missingIdentity) }
        guard message.subject.count <= 500, message.sender.count <= 500 else { return .skip(.oversizedHeaders) }
        return .classify(message)
    }
}
