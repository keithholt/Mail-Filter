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
        try require(try parsePoliticalLabel("POLITICAL") == .political && parsePoliticalLabel("NOT-POLITICAL") == .notPolitical, "string labels tolerate harmless capitalization")
        let positive = Classification(decision: try parsePoliticalLabel("political"), reason: "Campaign advertising", evidence: nil)
        try require(positive.decision == .political && positive.reason == "Campaign advertising", "political label parses without JSON generation")
        let negative = Classification(decision: try parsePoliticalLabel("not-political"), reason: "A receipt", evidence: nil)
        try require(negative.decision == .notPolitical, "negative label stays negative")
        let campaignMessage = message("Support our campaign to elect a senator.")
        try require(try validatePoliticalEvidence(positive, message: campaignMessage, terms: ["campaign"]) != nil, "campaign is accepted as evidence for a positive model decision")
        let officeMessage = message("A mass appeal from the Vice President to support the party.")
        try require(try validatePoliticalEvidence(positive, message: officeMessage, terms: ["Vice President"]) != nil, "political office can verify a positive without a politician-name allowlist")
        try require(try validatePoliticalEvidence(negative, message: campaignMessage, terms: ["campaign"]) == nil, "campaign vocabulary cannot promote a negative")
        try require(!hasPoliticalTerm("utm_campaign=retail", terms: ["campaign"]), "tracking parameter names are not mistaken for campaign text")
        try require(try parsePoliticalLabel("```text\npolitical\n```") == .political && parsePoliticalLabel("not political") == .notPolitical, "harmless label formatting is accepted")
        for text in ["", " \n\t\r"] {
            do { _ = try parsePoliticalLabel(text); throw ToolError("empty model text accepted") }
            catch let error as ModelLabelError {
                try require(error.kind == .emptyResponse, "empty and blank replies have a distinct failure")
            }
        }
        for label in ["\u{FEFF}political\u{200E}", "\u{2060}\" political \"\u{200F}", "```text\r\npolitical\r\n```"] {
            try require(try parsePoliticalLabel(label) == .political, "boundary formatting preserves a whole positive label")
        }
        try require(try parsePoliticalLabel("\u{FEFF}not-political\u{200E}") == .notPolitical,
                    "boundary normalization cannot promote a negative")
        do { _ = try parsePoliticalLabel("polit\u{200E}ical"); throw ToolError("internal invisible accepted") }
        catch let error as ModelLabelError {
            try require(error.kind == .invalidLabel && error.diagnosticReply.contains("U+200E"), "explicit diagnostics expose invisible suffixes without guessing a label")
        }
        var metrics = ModelRequestMetrics(status: .emptyResponse, section: 1, sections: 2, excerptCharacters: 6000,
            sectionCharacters: 3000, maximumSectionCharacters: 3000, instructionTokens: 500, promptTokens: 1000,
            tokenCountEstimated: false, contextTokens: 4096, responseTokenLimit: 64,
            elapsedMilliseconds: 5000, responseCharacters: 0, responseBytes: 0, inputTokens: 1500, outputTokens: 64,
            reasoningTokens: 64, physicalMemoryMiB: 18432, memoryPressure: "unknown", thermalState: "nominal")
        try require(metrics.valid && metrics.summary.contains("responseChars=0") && metrics.summary.contains("outputLimitReached=true")
            && metrics.summary.contains("reasoningTokens=64"), "empty response measurements distinguish token use from visible output")
        try require(try JSONDecoder().decode(ModelRequestMetrics.self, from: JSONEncoder().encode(metrics)) == metrics,
                    "content-free request measurements round trip")
        metrics.memoryPressure = "private-email-content"
        try require(!metrics.valid && metrics.summary == "metrics=invalid", "arbitrary content cannot enter measurement summaries")
        try require(ClassificationRequest.responseTokens == 256 && (1...3).map(ClassificationRequest.sectionCharacters(forAttempt:)) == [3000, 1500, 1500],
                    "new generation budgets reserve output headroom and retain bounded retries")
        var invalidRejected = false
        do {
            _ = try parsePoliticalLabel("junk")
        } catch { invalidRejected = true }
        try require(invalidRejected, "unsupported decision fails safely")
        for text in ["political\nnot-political", "This might be political.", "{\"decision\":\"political\"}"] {
            var rejected = false
            do { _ = try parsePoliticalLabel(text) } catch { rejected = true }
            try require(rejected, "conflicting, speculative or non-label responses cannot reach a move")
        }
        do {
            _ = try parsePoliticalLabel("Sorry, I can't help with political content.")
            throw ToolError("refusal was accepted")
        } catch let failure as ModelLabelError { try require(failure.kind == .refusal && !failure.localizedDescription.contains("political content"), "refusal text stays out of routine error output") }
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
        for attempt in 1...3 {
            let retried = try await longRequest.sections(promptBudget: 20_000,
                maximumCharacters: ClassificationRequest.sectionCharacters(forAttempt: attempt), tokenCount: { $0.count / 4 })
            try require(retried.count <= ClassificationRequest.maximumSections && body.prefix(6000).allSatisfy { char in retried.contains { $0.contains(char) } },
                        "every retry covers the complete first 6000 characters within the section bound")
        }
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
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundled = try String(contentsOf: sourceRoot.appendingPathComponent("MacApp/Resources/filter.txt"), encoding: .utf8)
        let cliPolicy = try String(contentsOf: sourceRoot.appendingPathComponent("prompts/filter.txt"), encoding: .utf8)
        try require(bundled == cliPolicy && !bundled.contains("Return a decision and a short explanation"),
                    "native and CLI defaults do not conflict with the whole-label contract")
        let oldPolicy = bundled.replacingOccurrences(of: "The application controls the response format and separately verifies source evidence when keywords are configured before moving a positive to Junk.",
            with: "Return a decision and a short explanation of the message's purpose. The application separately verifies evidence before moving a positive to Junk.")
        let policyStore = SharedStore(directory: storeURL.appendingPathComponent("format-migration"))
        var prior = settings
        prior.configuration = try FilteringConfiguration.make(selectedNames: ["Sample"], inventory: [.init(id: "sample", name: "Sample", addresses: ["me@example.com"])],
            rules: oldPolicy, evidenceTerms: [], mode: "dry-run")
        try policyStore.save(prior)
        _ = try policyStore.protection.reserve(messageID: "retained@example.org")
        try require(try policyStore.updateStandardPrompt(bundled), "actual previous shipped policy receives the response-format correction")
        let migrated = try policyStore.settings()
        try require(migrated.configuration!.rules == bundled && migrated.configuration!.evidenceTerms.isEmpty
                    && migrated.paused && migrated.configuration!.mode == "dry-run" && migrated.revision != prior.revision,
                    "format migration preserves empty keywords and operating preferences while invalidating in-flight work")
        try require(try policyStore.protection.contains(messageID: "retained@example.org") && !policyStore.updateStandardPrompt(bundled),
                    "format migration preserves recovery and is idempotent")
        let version11Store = SharedStore(directory: storeURL.appendingPathComponent("version11"))
        var version11Settings = settings
        version11Settings.configuration = try FilteringConfiguration.make(selectedNames: ["Sample"], inventory: [.init(id: "sample", name: "Sample", addresses: ["me@example.com"])],
            rules: "Custom retained policy", evidenceTerms: PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.version11Additions, mode: "dry-run")
        try version11Store.save(version11Settings)
        try require(try version11Store.updateStandardVerificationWords(), "existing version-11 standard list receives campaign and office terms")
        let version11Updated = try version11Store.settings()
        try require(version11Updated.configuration!.evidenceTerms.suffix(3) == ["campaign", "Vice President", "Paid for by"] && version11Updated.configuration!.rules == "Custom retained policy",
                    "campaign upgrade preserves saved filtering instructions and appends only missing words")
        try require(try !version11Store.updateStandardVerificationWords(), "campaign upgrade does not duplicate words on reopen")
        let version12Store = SharedStore(directory: storeURL.appendingPathComponent("version12"))
        var version12Settings = settings
        version12Settings.paused = false
        version12Settings.configuration = try FilteringConfiguration.make(selectedNames: ["Sample"], inventory: [.init(id: "sample", name: "Sample", addresses: ["me@example.com"])],
            rules: "Custom retained policy", evidenceTerms: PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.version12Additions, mode: "apply")
        try version12Store.save(version12Settings)
        _ = try version12Store.protection.reserve(messageID: "restored-v12@example.com")
        try require(try version12Store.updateStandardVerificationWords(), "version-12 standard vocabulary receives sponsorship phrase")
        let version12Updated = try version12Store.settings()
        try require(version12Updated.configuration!.evidenceTerms == version12Settings.configuration!.evidenceTerms + ["Paid for by"], "sponsorship update appends exactly the missing phrase")
        try require(version12Updated.configuration!.rules == version12Settings.configuration!.rules
                    && version12Updated.configuration!.mode == "apply" && !version12Updated.paused
                    && version12Updated.inventory == version12Settings.inventory
                    && version12Updated.selectedAccountIDs == version12Settings.selectedAccountIDs,
                    "sponsorship update preserves instructions, apply mode, pause state and account selection")
        try require(version12Updated.revision != version12Settings.revision, "sponsorship update invalidates stale policy results")
        try require(try version12Store.protection.contains(messageID: "restored-v12@example.com"), "sponsorship update retains restored-message protection")
        try require(try !version12Store.updateStandardVerificationWords(), "sponsorship update is idempotent")
        print("Passed \(count) label validation, token budgeting, excerpt coverage and policy-upgrade checks; no model generation or real Mail actions")
    }
}
