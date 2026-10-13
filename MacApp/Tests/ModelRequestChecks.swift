import Foundation
import FoundationModels
import CryptoKit

@main
struct ModelRequestChecks {
    static var count = 0
    static func require(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try value() else { throw ToolError(name) }
        count += 1
    }
    static func message(_ body: String) -> MailMessage {
        MailMessage(accountID: "private-account-id", account: "Private account", id: 1234,
            messageID: "private-recovery-identity@example.com", subject: "Campaign appeal", sender: "Sender <sender@example.com>",
            body: body, truncated: false, ownAddresses: ["private-address@example.com"])
    }
    @MainActor
    static func main() async throws {
        let schema = try PoliticalModel.schema()
        let encodedSchema = String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
        try require(encodedSchema.contains("political") && encodedSchema.contains("not-political"), "guided schema includes both classification choices")
        let positive = try PoliticalModel.decode(GeneratedContent(json: "{\"decision\":\"political\",\"reason\":\"Campaign advertising\"}"))
        try require(positive.decision == .political && positive.reason == "Campaign advertising", "guided result is read directly without string JSON cleanup")
        let negative = try PoliticalModel.decode(GeneratedContent(json: "{\"decision\":\"not-political\",\"reason\":\"A receipt\"}"))
        try require(negative.decision == .notPolitical, "guided negative stays negative")
        let campaignMessage = message("Support our campaign to elect a senator.")
        try require(try validatePoliticalEvidence(positive, message: campaignMessage, terms: ["campaign"]) != nil, "campaign is accepted as evidence for a positive model decision")
        let officeMessage = message("A mass appeal from the Vice President to support the party.")
        try require(try validatePoliticalEvidence(positive, message: officeMessage, terms: ["Vice President"]) != nil, "political office can verify a positive without a politician-name allowlist")
        try require(try validatePoliticalEvidence(negative, message: campaignMessage, terms: ["campaign"]) == nil, "campaign vocabulary cannot promote a negative")
        try require(!hasPoliticalTerm("utm_campaign=retail", terms: ["campaign"]), "tracking parameter names are not mistaken for campaign text")
        let noReason = try PoliticalModel.decode(GeneratedContent(json: "{\"decision\":\"political\",\"reason\":\"\"}"))
        try require(noReason.decision == .political && !noReason.reason.isEmpty, "empty explanation does not discard a valid positive")
        var invalidRejected = false
        do {
            _ = try PoliticalModel.decode(GeneratedContent(json: "{\"decision\":\"junk\",\"reason\":\"Marketing\"}"))
        } catch { invalidRejected = true }
        try require(invalidRejected, "unsupported decision fails safely")
        let request = ClassificationRequest(message: message("Please support our election campaign."))
        let prompt = try request.prompt(body: request.message.body, divided: false)
        try require(!prompt.contains("private-account") && !prompt.contains("Private account") && !prompt.contains("private-recovery") && !prompt.contains("private-address"), "model input excludes account, recovery identity and own addresses")
        let small = try await request.sections(promptBudget: 1000, tokenCount: { $0.count / 4 })
        try require(small == [request.message.body], "ordinary email uses one request")
        let body = (0..<6500).map { String(UnicodeScalar(0xE000 + $0)!) }.joined()
        let longRequest = ClassificationRequest(message: message(body))
        let sections = try await longRequest.sections(promptBudget: 1600, tokenCount: { $0.count / 2 })
        try require(sections.count > 1 && sections.count <= ClassificationRequest.maximumSections, "dense input divides into bounded sections")
        for section in sections {
            try require(try longRequest.prompt(body: section, divided: true).count / 2 <= 1600, "every section fits the supplied token budget")
        }
        try require(body.prefix(6000).allSatisfy { char in sections.contains { $0.contains(char) } }, "all first 6000 characters remain covered")
        try require(!sections.contains { $0.contains(body.last!) }, "content after the approved excerpt is excluded")
        let divided = try longRequest.prompt(body: sections[0], divided: true)
        try require(divided.contains("openingContext") && divided.contains("closingContext"), "divided requests retain solicitation and sponsorship context")
        let forced = try await longRequest.sections(promptBudget: 20_000, maximumCharacters: 1500, tokenCount: { $0.count / 4 })
        try require(forced.allSatisfy { $0.count <= 1500 }, "context retries change the request size without dropping content")
        do {
            _ = try await request.sections(promptBudget: 0, tokenCount: { _ in 1 })
            throw ToolError("invalid instructions budget was accepted")
        } catch ClassificationRequestError.instructionsTooLong { count += 1 }
        do {
            _ = try await request.sections(promptBudget: 1, tokenCount: { _ in 500 })
            throw ToolError("unfittable section was accepted")
        } catch ClassificationRequestError.sectionTooLarge { count += 1 }
        if #available(macOS 27.0, *) {
            let failure = LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "private-email-content"))
            try require(PoliticalModel.isContextLimit(failure), "current context errors select adaptive retries")
        }
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let store = SharedStore(directory: storeURL)
        var settings = NativeSettings()
        settings.inventory = [.init(id: "sample", name: "Sample", addresses: ["me@example.com"])]
        settings.selectedAccountIDs = ["sample"]
        settings.paused = true
        settings.configuration = try FilteringConfiguration.make(selectedNames: ["Sample"], inventory: [.init(id: "sample", name: "Sample", addresses: ["me@example.com"])], rules: "Old standard", evidenceTerms: PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.firstAdditions, mode: "dry-run")
        try store.save(settings)
        _ = try store.protection.reserve(messageID: "returned@example.com")
        let digest = SHA256.hash(data: Data("Old standard".utf8)).map { String(format: "%02x", $0) }.joined()
        try require(try store.updateStandardPrompt("New standard", replacingDigest: digest), "untouched standard prompt upgrades")
        try require(try store.updateStandardVerificationWords(), "version-9 standard vocabulary receives issue terms")
        let upgraded = try store.settings()
        try require(upgraded.configuration!.rules == "New standard" && upgraded.configuration!.evidenceTerms.contains("Second Amendment") && upgraded.configuration!.evidenceTerms.contains("abortion"), "requested issue policy and verification words stay aligned")
        try require(upgraded.paused && upgraded.configuration!.mode == "dry-run" && upgraded.inventory == settings.inventory && upgraded.selectedAccountIDs == settings.selectedAccountIDs, "policy upgrade retains all operational settings")
        try require(try store.protection.contains(messageID: "returned@example.com"), "policy upgrade retains restored-message protection")
        try require(try !store.updateStandardPrompt("Other standard") && !store.updateStandardVerificationWords(), "custom prompts and repeated upgrades remain unchanged")
        let version11Store = SharedStore(directory: storeURL.appendingPathComponent("version11"))
        var version11Settings = settings
        version11Settings.configuration = try FilteringConfiguration.make(selectedNames: ["Sample"], inventory: [.init(id: "sample", name: "Sample", addresses: ["me@example.com"])],
            rules: "Custom retained policy", evidenceTerms: PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.version11Additions, mode: "dry-run")
        try version11Store.save(version11Settings)
        try require(try version11Store.updateStandardVerificationWords(), "existing version-11 standard list receives campaign and office terms")
        let version11Updated = try version11Store.settings()
        try require(version11Updated.configuration!.evidenceTerms.suffix(2) == ["campaign", "Vice President"] && version11Updated.configuration!.rules == "Custom retained policy",
                    "campaign upgrade preserves saved filtering instructions and appends only missing words")
        try require(try !version11Store.updateStandardVerificationWords(), "campaign upgrade does not duplicate words on reopen")
        print("Passed \(count) guided schema, token budgeting, excerpt coverage and policy-upgrade checks; no model generation or real Mail actions")
    }
}
