import Foundation

struct DryRunCheckFailure: Error { let name: String }

@main
@MainActor
struct DryRunChecks {
    static func require(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !value() { throw DryRunCheckFailure(name: name) }
    }
    static func isSkipped(_ input: FilteringInput, _ reason: FilteringSkipReason) -> Bool {
        if case .skip(let actual) = input { return actual == reason }
        return false
    }
    static func main() async throws {
        let inventory = [FilteringAccount(id: "example-account", name: "Example", addresses: ["me@example.com"]), FilteringAccount(id: "other-account", name: "Other", addresses: ["me@other.example"])]
        let configuration = try FilteringConfiguration.make(selectedNames: ["Example"], inventory: inventory,
            rules: "Classify only political solicitations, never ordinary marketing.", evidenceTerms: ["political action committee", "election"])
        try require(configuration.selectedRecipientAddresses == ["me@example.com"], "selected account addresses only")
        try require(configuration.ownAddresses == ["me@example.com", "me@other.example"], "all accounts contribute protected addresses")
        let body = DecodedMailBody(text: "Donate to our election campaign.", characterCount: 32, truncated: false)
        let fromOtherOwnAccount = configuration.input(messageID: "self@example.com", sender: "Other Me <ME@OTHER.EXAMPLE>", subject: "Reminder", recipients: ["me@example.com"], body: body)
        try require(isSkipped(fromOtherOwnAccount, .selfMail), "cross-account self mail is protected even with political body")
        try require(isSkipped(configuration.input(messageID: "external@example.org", sender: "sender@example.org", subject: "Campaign", recipients: ["me@other.example"], body: body), .recipientNotSelected), "unselected recipient is excluded")
        try require(isSkipped(configuration.input(messageID: "external@example.org", sender: "sender@example.org", subject: "Campaign", recipients: [], body: body), .recipientNotSelected), "unknown delivery address is excluded")
        let empty = DecodedMailBody(text: "\n\u{FEFF}", characterCount: 2, truncated: false)
        try require(isSkipped(configuration.input(messageID: "id", sender: "sender@example.org", subject: "Subject only", recipients: ["me@example.com"], body: empty), .emptyBody), "invisible-only body protected")
        try require(isSkipped(configuration.input(messageID: nil, sender: "sender@example.org", subject: "Campaign", recipients: ["me@example.com"], body: body), .missingIdentity), "missing identity excluded")
        try require(isSkipped(configuration.input(messageID: "id", sender: "sender@example.org", subject: String(repeating: "s", count: 501), recipients: ["me@example.com"], body: body), .oversizedHeaders), "oversized subject excluded")
        guard case .classify(let candidate) = configuration.input(messageID: "external@example.org", sender: "sender@example.org", subject: "Campaign", recipients: ["ME@EXAMPLE.COM"], body: body) else {
            throw DryRunCheckFailure(name: "selected external mail must reach classifier")
        }
        try require(candidate.canMove && !candidate.isFromSelf, "eligible read-only candidate reuses CLI guards")
        let result = try parseClassification("{\"decision\":\"political\",\"reason\":\"Election fundraising\",\"evidence\":\"election campaign\"}")
        try require(try validatePoliticalEvidence(result, message: candidate, terms: configuration.evidenceTerms) == "election campaign", "verified positive evidence")
        var ordinary = candidate
        ordinary.subject = "Let's keep in touch!"
        ordinary.body = "Visit our social media pages. Unsubscribe."
        var rejected = false
        do { _ = try validatePoliticalEvidence(result, message: ordinary, terms: configuration.evidenceTerms) }
        catch { rejected = true }
        try require(rejected, "generic marketing cannot pass positive political verification")
        try require(try validatePoliticalEvidence(result, message: ordinary, terms: []) == nil,
                    "empty list explicitly bypasses secondary evidence validation")
        let negative = try parseClassification("{\"decision\":\"not-political\",\"reason\":\"Ordinary correspondence\",\"evidence\":\"\"}")
        try require(try validatePoliticalEvidence(negative, message: candidate, terms: configuration.evidenceTerms) == nil, "keyword cannot promote a negative model decision")
        var pac = candidate
        pac.subject = "Special offer"
        pac.body = "Paid for by Example Political Action Committee."
        let missingQuote = try parseClassification("{\"decision\":\"political\",\"reason\":\"PAC solicitation\",\"evidence\":\"incorrect quote\"}")
        try require(try validatePoliticalEvidence(missingQuote, message: pac, terms: configuration.evidenceTerms) == "Paid for by Example Political Action Committee", "PAC body evidence fallback reused")
        let previousTerms = PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.version12Additions
        let standardTerms = PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.additions
        let labelOnlyPositive = Classification(decision: .political, reason: "Political solicitation", evidence: nil)
        var sponsored = candidate
        sponsored.subject = "Respectfully asking for $1"
        sponsored.body = "I'm asking everyone for just $1.\nPaid for by Alex Morgan and Jamie Reed for Example State."
        var sponsorshipPreviouslyRejected = false
        do { _ = try validatePoliticalEvidence(labelOnlyPositive, message: sponsored, terms: previousTerms) }
        catch { sponsorshipPreviouslyRejected = true }
        try require(sponsorshipPreviouslyRejected, "sponsorship-only positive reproduces the previous vocabulary gap")
        try require(try validatePoliticalEvidence(labelOnlyPositive, message: sponsored, terms: standardTerms) == "Paid for by Alex Morgan and Jamie Reed for Example State", "fundraising sponsorship verifies a label-only political positive")
        sponsored.subject = "This took me a long time to write."
        sponsored.body = "Read my personal message to you.\nPAID FOR BY Morgan for Example State, Inc. Unsubscribe."
        try require(try validatePoliticalEvidence(labelOnlyPositive, message: sponsored, terms: standardTerms) == "PAID FOR BY Morgan for Example State, Inc", "sponsorship verifies an indirect appeal without requiring donation language")
        sponsored.body = "Your lunch was paid for by your employer."
        try require(try validatePoliticalEvidence(negative, message: sponsored, terms: standardTerms) == nil, "ordinary payment wording never promotes a negative model decision")
        sponsored.body = String(repeating: "x", count: 6001) + "\nPaid for by Morgan for Example State."
        var unseenSponsorshipRejected = false
        do { _ = try validatePoliticalEvidence(labelOnlyPositive, message: sponsored, terms: standardTerms) }
        catch { unseenSponsorshipRejected = true }
        try require(unseenSponsorshipRejected, "sponsorship outside the classified excerpt remains insufficient")
        let selfSponsorship = DecodedMailBody(text: "Paid for by Morgan for Example State.", characterCount: 42, truncated: false)
        try require(isSkipped(configuration.input(messageID: "self-sponsorship@example.com", sender: "me@other.example", subject: "Forwarded appeal", recipients: ["me@example.com"], body: selfSponsorship), .selfMail), "sponsorship wording cannot bypass own-sender protection")
        let long = DecodedMailBody(text: body.text, characterCount: 8_000, truncated: true)
        guard case .classify(let longCandidate) = configuration.input(messageID: "long", sender: "sender@example.org", subject: "Campaign", recipients: ["me@example.com"], body: long) else { throw DryRunCheckFailure(name: "long excerpt should remain eligible") }
        try require(longCandidate.truncated, "long excerpts remain eligible and marked truncated")
        var mismatch = false
        do { _ = try FilteringConfiguration.make(selectedNames: ["Missing"], inventory: inventory, rules: "Rules", evidenceTerms: ["election"]) }
        catch { mismatch = true }
        try require(mismatch, "unknown account cannot fall back to all accounts")
        let invalid = FilteringConfiguration(schemaVersion: 2, mode: "unknown", selectedRecipientAddresses: ["me@example.com"], ownAddresses: ["me@example.com"], rules: "Rules", evidenceTerms: ["election"], legacyAccountIDs: ["example-account"], protectedCLIIdentities: [])
        var modeRejected = false
        do { try invalid.validate() } catch { modeRejected = true }
        try require(modeRejected, "unknown mode cannot enable moves")
        let incomplete = FilteringConfiguration(schemaVersion: 2, mode: "dry-run", selectedRecipientAddresses: ["me@example.com"], ownAddresses: ["me@other.example"], rules: "Rules", evidenceTerms: ["election"], legacyAccountIDs: ["example-account"], protectedCLIIdentities: [])
        var incompleteRejected = false
        do { try incomplete.validate() } catch { incompleteRejected = true }
        try require(incompleteRejected, "selected identities must also be protected own addresses")
        let roundTrip = try JSONDecoder().decode(FilteringConfiguration.self, from: JSONEncoder().encode(configuration))
        try roundTrip.validate()
        try require(roundTrip.ownAddresses == configuration.ownAddresses, "private snapshot round-trip")
        try require(configuration.mode == "apply", "default configuration requests Junk moves")
        let preview = try FilteringConfiguration.make(selectedNames: ["Example"], inventory: inventory, rules: "Rules", evidenceTerms: ["election"], mode: "dry-run")
        try require(preview.mode == "dry-run", "explicit preview configuration supported")
        try require(configuration.legacyAccountIDs == ["example-account", "other-account"], "all account IDs available for inherited protection")
        let old = FilteringConfiguration(schemaVersion: 1, mode: "dry-run", selectedRecipientAddresses: ["me@example.com"], ownAddresses: ["me@example.com"], rules: "Rules", evidenceTerms: ["election"], legacyAccountIDs: ["example-account"], protectedCLIIdentities: [])
        var oldRejected = false
        do { try old.validate() } catch { oldRejected = true }
        try require(oldRejected, "obsolete configuration requires fresh export")
        print("Passed 28 configuration, account protection and political-evidence checks (synthetic inputs only)")
        try await scheduling()
    }

    static func scheduling() async throws {
        let scheduler = InspectionScheduler(maximumPending: 2, maximumRecent: 1)
        var releaseFirst: CheckedContinuation<Void, Never>?
        var active = 0
        var peak = 0
        var order: [String] = []
        let first = Task { @MainActor in
            await scheduler.perform(fingerprint: "first") {
                active += 1; peak = max(peak, active); order.append("first")
                await withCheckedContinuation { releaseFirst = $0 }
                active -= 1
                return true
            }
        }
        while releaseFirst == nil { await Task.yield() }
        let duplicate = await scheduler.perform(fingerprint: "first") { throwaway(); return true }
        try require(duplicate == .duplicate, "in-flight duplicate excluded")
        let second = Task { @MainActor in
            await scheduler.perform(fingerprint: "second") {
                active += 1; peak = max(peak, active); order.append("second"); active -= 1
                return true
            }
        }
        while scheduler.pendingCount < 2 { await Task.yield() }
        let overflow = await scheduler.perform(fingerprint: "third") { throwaway(); return true }
        try require(overflow == .queueFull && scheduler.pendingCount == 2, "bounded queue rejects excess job without retaining it")
        releaseFirst!.resume()
        let firstResult = await first.value
        let secondResult = await second.value
        try require(firstResult == .completed && secondResult == .completed, "queued operations completed")
        try require(peak == 1 && order == ["first", "second"] && scheduler.pendingCount == 0, "inference serialized and pending bookkeeping cleared")
        let cached = await scheduler.perform(fingerprint: "second") { throwaway(); return true }
        try require(cached == .duplicate, "successful completed callback deduplicated")
        var ranAgain = false
        _ = await scheduler.perform(fingerprint: "first") { ranAgain = true; return true }
        try require(ranAgain, "old cache entry evicted within bounded memory")
        var retries = 0
        _ = await scheduler.perform(fingerprint: "failure") { retries += 1; return false }
        _ = await scheduler.perform(fingerprint: "failure") { retries += 1; return false }
        try require(retries == 2 && scheduler.pendingCount == 0, "failed inference remains retryable")
        print("Passed 7 burst, deduplication and retry scheduling checks (no model calls)")
    }

    static func throwaway() { preconditionFailure("Rejected operation must never run") }
}
