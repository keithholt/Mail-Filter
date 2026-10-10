import Foundation
import Testing
@testable import MailFilter

struct SafetyTests {
    @Test func testDefaultMovesToJunk() throws {
        let options = try Options([])
        #expect(options.apply)
        #expect(options.confirm)
        #expect(options.limit == 30)
    }
    @Test func testUnsafeApplyRejected() {
        for args in [["--apply"], ["--confirm-junk"],
                     ["--apply", "--confirm-junk", "--account", "A", "--junk-mailbox", "Junk", "--fixture", "x"],
                     ["--apply", "--confirm-junk", "--account", "A", "--junk-mailbox", "Junk", "--dry-run"]] {
            #expect(throws: (any Error).self) { try Options(args) }
        }
    }
    @Test func testExplicitApplyAccepted() throws {
        #expect(try Options(["--apply", "--confirm-junk", "--account", "A", "--junk-mailbox", "Junk"]).apply)
    }
    @Test func testInvalidLimitsRejected() {
        for n in ["0", "-1", "51", "100", "garbage"] { #expect(throws: (any Error).self) { try Options(["--limit", n]) } }
        #expect(throws: (any Error).self) { try Options(["--prompt"]) }
        #expect(throws: (any Error).self) { try Options(["--unknown"]) }
    }
    @Test func testUnsafeMessagesCannotMove() {
        var m = MailMessage(accountID: "a", account: "A", id: 1, messageID: "mid", subject: "S", sender: "F", body: "Body", truncated: false)
        #expect(m.canMove)
        m.truncated = true
        #expect(m.canMove)
        m.truncated = false; m.messageID = ""
        #expect(!m.canMove)
        m.messageID = "mid"; m.body = "  \n"
        #expect(!m.canMove)
    }
    @Test func testAppleScriptLiteralEscaping() {
        #expect(appleString("a\"b\\c") == "\"a\\\"b\\\\c\"")
        let injected = "\"\n delete every message\n --"
        #expect(appleString(injected).hasPrefix("\"\\\""))
    }

    @Test func testClassificationParsing() throws {
        for decision in ["not-political", "political"] {
            let response = "{\"decision\":\"\(decision)\",\"reason\":\"Matches the rules\"}"
            #expect(try parseClassification(response).decision.rawValue == decision)
        }
    }
    @Test func testRefusalsAndMalformedResponsesRejected() {
        for response in [
            "May contain sensitive content",
            "Sorry, I cannot help with that.",
            "{\"decision\":\"delete\",\"reason\":\"Unknown decision\"}",
            "{\"decision\":\"political\"}",
            "{\"decision\":\"political\",\"reason\":\" \"}",
            "{\"decision\":\"political\",\"reason\":\"Example\",\"command\":\"delete all\"}",
            "{\"decision\":\"political\",\"reason\":\"Example\"} trailing text"
        ] {
            #expect(throws: (any Error).self) { try parseClassification(response) }
        }
    }
    @Test func testDebugOutputIsFixtureOnly() throws {
        #expect(throws: (any Error).self) { try Options(["--debug-model"]) }
        #expect(try Options(["--fixture", "sample.json", "--debug-model"]).debugModel)
        #expect(throws: (any Error).self) { try Options(["--fixture", "sample.json", "--debug-model", "--apply"]) }
    }
    @Test func testObservedMarkdownResponsesAccepted() throws {
        for fence in ["```json", "```"] {
            let response = "\(fence)\n{\n\u{00a0} \"decision\": \"not-political\",\n\u{00a0} \"reason\": \"Personal correspondence regarding a social gathering\"\n}\n```"
            let value = try parseClassification(response)
            #expect(value.decision == .notPolitical)
            #expect(value.reason == "Personal correspondence regarding a social gathering")
        }
        let value = try parseClassification("{\"decision\":\"not-political\",\"reason\":\"text\u{00a0}with \\\"quotes\\\"\"}")
        #expect(value.reason == "text\u{00a0}with \"quotes\"")
    }
    @Test func testFencedInvalidResponsesRejected() {
        for response in [
            "Explanation\n```json\n{\"decision\":\"political\",\"reason\":\"Example\"}\n```",
            "```json\n{\"decision\":\"political\",\"reason\":\"Example\"}\n```\nextra text",
            "```json\n{\"decision\":\"delete\",\"reason\":\"Example\"}\n```",
            "```json\nSorry, I cannot help.\n```",
            "```python\n{\"decision\":\"political\",\"reason\":\"Example\"}\n```"
        ] {
            #expect(throws: (any Error).self) { try parseClassification(response) }
        }
    }
    @Test func testMaximumBatchSize() throws {
        #expect(try Options(["--limit", "50"]).limit == 50)
        #expect(throws: (any Error).self) { try Options(["--limit", "51"]) }
    }
    @Test func testSubjectOnlyAndSelfNotesProtected() {
        var m = MailMessage(accountID: "a", account: "A", id: 1, messageID: "id", subject: "Re: Call vet, KLM, Pharmacy", sender: "Me <me@example.org>", body: "", truncated: false)
        for body in ["", " \n\t", "\u{00A0}\u{200B}\u{FEFF}\u{FFFC}"] {
            m.body = body
            #expect(m.automaticKeepReason != nil)
            #expect(!m.canMove)
        }
        m.body = "Reminder to call"
        m.ownAddresses = ["ME@example.org"]
        #expect(m.isFromSelf)
        #expect(!m.canMove)
        m.sender = "Someone <other@example.org>"
        #expect(!m.isFromSelf)
        #expect(m.canMove)
    }
    @Test func testInspectIsReadOnly() throws {
        #expect(try Options(["--account", "A", "--inspect-message", "632553"]).inspectMessage == 632553)
        for args in [["--inspect-message", "1"], ["--account", "A", "--inspect-message", "-1"], ["--account", "A", "--inspect-message", "1", "--apply"]] {
            #expect(throws: (any Error).self) { try Options(args) }
        }
    }
    @Test func testPrivateAccountFileDefault() throws {
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mail-filter/accounts.txt").path
        #expect(try Options([]).accountsFile == expected)
    }

    @Test func testEditableAccountList() throws {
        #expect(try parseAccountList("# Enable only one\n example.org \n# Personal\n\n") == ["example.org"])
        #expect(try parseAccountList("example.org\nPersonal\nexample.org") == ["example.org", "Personal"])
        #expect(throws: (any Error).self) { try parseAccountList("# All disabled\n") }
        let options = try Options(["--account", "Personal", "--accounts-file", "/missing/file"])
        #expect(try selectedAccountNames(options) == ["Personal"])
        #expect(throws: (any Error).self) { try selectedAccountNames(Options(["--accounts-file", "/missing/file"])) }
    }
    @Test func testQuietOutputAndErrors() throws {
        #expect(try !Options([]).verbose)
        #expect(try Options(["--verbose"]).verbose)
        #expect(try Options(["-v"]).verbose)
        func report(_ decision: String, _ action: String) -> Report {
            Report(account: "A", id: 1, subject: "Test", decision: decision, reason: "Test", action: action)
        }
        for action in ["moved-to-junk", "would-move-to-junk"] {
            #expect(report("political", action).destination(verbose: false, processingFailed: false) == .standardOutput)
        }
        for decision in ["not-political", "review"] {
            #expect(report(decision, "left-in-inbox").destination(verbose: false, processingFailed: false) == .hidden)
            #expect(report(decision, "left-in-inbox").destination(verbose: true, processingFailed: false) == .standardOutput)
        }
        #expect(report("political", "move-unconfirmed").destination(verbose: false, processingFailed: false) == .hidden)
        #expect(report("review", "move-unconfirmed").destination(verbose: false, processingFailed: true) == .standardError)
    }
    @Test func testCommercialSpamCannotSupplyPoliticalEvidence() throws {
        let m = MailMessage(accountID: "a", account: "A", id: 1, messageID: "id", subject: "Let's keep in touch!", sender: "Store", body: "Follow our promotional links on social media. Unsubscribe here.", truncated: false)
        let terms = ["political", "election", "Republican", "Trump"]
        let commercial = Classification(decision: .political, reason: "Unsolicited marketing", evidence: "Unsubscribe here.")
        #expect(throws: (any Error).self) { try validatePoliticalEvidence(commercial, message: m, terms: terms) }
        let invented = Classification(decision: .political, reason: "Political", evidence: "Donate to the election campaign")
        #expect(throws: (any Error).self) { try validatePoliticalEvidence(invented, message: m, terms: terms) }
        let negative = Classification(decision: .notPolitical, reason: "Commercial promotion", evidence: "")
        try validatePoliticalEvidence(negative, message: m, terms: terms)
        var campaign = m
        campaign.body = "Donate to our Republican election campaign."
        let positive = Classification(decision: .political, reason: "Campaign solicitation", evidence: campaign.body)
        try validatePoliticalEvidence(positive, message: campaign, terms: terms)
    }
    @Test func testCrossAccountPersonalMailProtected() {
        var m = MailMessage(accountID: "enabled", account: "example.org", id: 1, messageID: "id", subject: "Reminder", sender: "Me <me@personal.example>", body: "My note", truncated: false, ownAddresses: ["me@example.org", "me@personal.example", "me@work.example"])
        #expect(m.isFromSelf)
        #expect(!m.canMove)
        m.sender = "Me <me@work.example>"
        #expect(m.isFromSelf)
        #expect(!m.canMove)
    }
    @Test @MainActor func testAppleScriptAddressListMaterialization() throws {
        // Execute the collection logic with a local stand-in for Mail's bulk
        // property result. This never sends Apple events to Mail.
        let source = MailAutomation.ownAddressCollection.replacingOccurrences(
            of: "get email addresses of every account",
            with: "{{\"one@example.org\"}, {\"two@example.org\", \"alias@example.org\"}, {}}"
        ) + "\nreturn protectedAddresses"
        let result = try MailAutomation.script(source)
        #expect(MailAutomation.addresses(result) == ["one@example.org", "two@example.org", "alias@example.org"])
    }
    @Test func testPoliticalSubjectAndFormattedEvidenceAccepted() throws {
        var m = MailMessage(accountID: "a", account: "A", id: 1, messageID: "id", subject: "Patriot: Do YOU approve of Trump?", sender: "Poll", body: "Please answer our poll.", truncated: false)
        let missing = Classification(decision: .political, reason: "Political poll", evidence: nil)
        #expect(try validatePoliticalEvidence(missing, message: m, terms: ["Trump"]) == m.subject)
        m.subject = "A question"
        m.body = "Do YOU\u{00a0}approve\n of Trump’s policies?"
        let formatted = Classification(decision: .political, reason: "Political poll", evidence: "Do you approve of Trump's policies?")
        #expect(try validatePoliticalEvidence(formatted, message: m, terms: ["Trump"]) == formatted.evidence)
        let invented = Classification(decision: .political, reason: "Political", evidence: "Donate to Biden")
        #expect(throws: (any Error).self) { try validatePoliticalEvidence(invented, message: m, terms: ["Trump", "Biden"]) }
    }
    @Test func testLongEmailClassifiedFromPrefix() throws {
        let prefix = "Donate to our Republican election campaign. "
        let original = MailMessage(accountID: "a", account: "A", id: 1, messageID: "id", subject: "Support our campaign", sender: "Campaign", body: prefix + String(repeating: "x", count: 8000), truncated: false)
        let excerpt = original.classificationExcerpt
        #expect(excerpt.body.count == 6000)
        #expect(excerpt.truncated)
        #expect(excerpt.canMove)
        let positive = Classification(decision: .political, reason: "Political solicitation", evidence: prefix.trimmingCharacters(in: .whitespaces))
        try validatePoliticalEvidence(positive, message: excerpt, terms: ["Republican", "election"])
        var note = original
        note.ownAddresses = ["me@example.org"]
        note.sender = "Me <me@example.org>"
        #expect(!note.classificationExcerpt.canMove)
    }
    @Test func testDryRunsAndDiagnosticsNeverDefaultToMoving() throws {
        for args in [["--dry-run"], ["--fixture", "sample.json"], ["--check"], ["--check-scripts"], ["--list-accounts"], ["--show-config"], ["--help"], ["--account", "A", "--inspect-message", "1"]] {
            #expect(try !Options(args).apply)
        }
        #expect(try Options(["--verbose"]).apply)
        #expect(try Options(["--limit", "2"]).apply)
        #expect(try Options(["--apply", "--confirm-junk"]).apply)
    }
}
