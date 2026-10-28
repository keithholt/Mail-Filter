import Foundation
import FoundationModels

struct InjectedCheckFailure: Error { let name: String }

/// Uses the production request/parser/retry/scheduler/final-action code with a
/// scripted transport and disposable private stores. No MailKit action is made.
@main
@MainActor
struct FailureInjectionChecks {
    static var checks = 0
    static var scenarios = 0
    static var root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-filter-faults-" + UUID().uuidString)

    static func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try value() else { throw InjectedCheckFailure(name: name) }
        checks += 1
    }

    @MainActor final class Harness {
        let store: SharedStore
        let classifier: NativeClassifier
        init(terms: [String] = ["campaign"], preview: Bool = false, allowOwnMail: Bool = false,
             attemptSeconds: TimeInterval = 1, totalSeconds: TimeInterval = 3,
             scheduler: InspectionScheduler? = nil,
             respond: @escaping (Int, String) async throws -> PoliticalModel.Reply) throws {
            scenarios += 1
            store = SharedStore(directory: root.appendingPathComponent(UUID().uuidString))
            var settings = NativeSettings()
            settings.configuration = try FilteringConfiguration.make(selectedNames: ["test"],
                inventory: [.init(id: "test", name: "test", addresses: ["me@example.com"]),
                            .init(id: "unchecked", name: "unchecked", addresses: ["me@other.example"])],
                rules: "Identify political appeals, never ordinary receipts.", evidenceTerms: terms,
                mode: preview ? "dry-run" : "apply")
            // Decode the same key in both compilations: production must ignore
            // even an explicitly true Dev setting copied into its JSON.
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
            object["filterOwnMailForTesting"] = allowOwnMail
            settings = try JSONDecoder().decode(NativeSettings.self, from: JSONSerialization.data(withJSONObject: object))
            try store.save(settings)
            // This holder avoids capturing a partially initialized Harness.
            let counter = Counter()
            let engine = PoliticalModel.Engine(contextSize: 4096, estimatedTokens: false,
                instructionTokens: { _ in 100 }, promptTokens: { ($0.utf8.count + 3) / 4 },
                respond: { _, prompt, limit in
                    counter.calls += 1; counter.prompts.append(prompt); counter.limits.append(limit)
                    return try await respond(counter.calls, prompt)
                })
            classifier = NativeClassifier(store: store, engine: engine, scheduler: scheduler,
                attemptSeconds: attemptSeconds, totalSeconds: totalSeconds, retryDelay: { _ in })
            self.counter = counter
        }

        private let counter: Counter
        var callCount: Int { counter.calls }
        var events: [NativeActivity] { get throws { try store.activity().recent } }
        var requestMetrics: [ModelRequestMetrics] { get throws { try events.compactMap(\.modelMetrics) } }
        func run(_ id: String = "test@example.org", text: String = "Please support our campaign.",
                 sender: String = "outside@example.org", recipients: [String] = ["me@example.com"]) async -> Bool {
            await classifier.inspect(messageID: id, sender: sender, subject: "An appeal", recipients: recipients,
                body: .init(text: text, characterCount: text.count, truncated: false))
        }
    }

    @MainActor final class Counter { var calls = 0; var prompts: [String] = []; var limits: [Int] = [] }
    static func reply(_ value: String) -> PoliticalModel.Reply {
        .init(content: value, inputTokens: 200, outputTokens: value.isEmpty ? 0 : 3, reasoningTokens: 0)
    }
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        throw InjectedCheckFailure(name: "test synchronization did not complete")
    }

    static func main() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        for (bad, status, category) in [("", "emptyResponse", "modelEmptyResponse"),
                                      (" \n\t", "blankResponse", "modelEmptyResponse"),
                                      ("private-invalid-reply-marker", "invalidLabel", "invalidModelResponse")] {
            let h = try Harness { call, _ in reply(call == 1 ? bad : "political") }
            let moved = await h.run()
            try check(moved && h.callCount == 2, "\(status) recovers on a bounded retry")
            try check(try h.events.contains { $0.outcome == "retryScheduled" && $0.category == category && $0.attempt == 1 }, "retry identifies \(category)")
            try check(try h.requestMetrics.contains { $0.status.rawValue == status }, "metrics distinguish \(status)")
            try check(try h.store.activity().junkRequested == 1 && h.store.protection.contains(messageID: "test@example.org"), "recovery reserves one protected Junk intent")
            let json = String(decoding: try JSONEncoder().encode(h.store.activity()), as: UTF8.self)
            try check(!json.contains("private-invalid-reply-marker") && !json.contains("outside@example.org") && !json.contains("Please support"), "ordinary metrics contain no raw response or message")
        }

        let exhausted = try Harness { _, _ in reply("") }
        let exhaustedMove = await exhausted.run()
        try check(!exhaustedMove, "empty exhaustion leaves in place")
        try check(exhausted.callCount == 3, "exactly three attempts at exhaustion")
        try check(try exhausted.events.contains { $0.outcome == "review" && $0.category == "modelEmptyResponse" && $0.attempt == 3 }, "exhaustion is diagnosed")
        try check(try !exhausted.store.protection.contains(messageID: "test@example.org"), "exhaustion never reserves recovery state")
        _ = await exhausted.run()
        try check(exhausted.callCount == 3, "duplicate callbacks cannot restart exhausted attempts")

        let malformed = try Harness { _, _ in reply("{\"decision\":\"political\"}") }
        let malformedMove = await malformed.run()
        try check(!malformedMove && malformed.callCount == 3, "malformed JSON never promotes a positive")
        let refusal = try Harness { _, _ in reply("I cannot help with that request.") }
        let refusedMove = await refusal.run()
        try check(!refusedMove && refusal.callCount == 1, "refusal is terminal without retries")
        let negative = try Harness { _, _ in reply("not-political") }
        let negativeMove = await negative.run()
        try check(!negativeMove && negative.callCount == 1, "valid negative is final even with a matching keyword")
        let unverified = try Harness { _, _ in reply("political") }
        let unverifiedMove = await unverified.run(text: "A receipt for your purchase.")
        try check(!unverifiedMove && unverified.callCount == 1, "unverifiable positive is terminal")
        try check(try unverified.events.contains { $0.category == "evidenceRejected" }, "keyword rejection differs from model errors")

        let noTerms = try Harness(terms: []) { _, _ in reply("political") }
        let unrestricted = await noTerms.run(text: "An appeal under a custom policy.")
        try check(unrestricted && noTerms.callCount == 1, "empty list disables keyword validation in final Junk gate")
        let noTermsNegative = try Harness(terms: []) { _, _ in reply("not-political") }
        let retainedNegative = await noTermsNegative.run()
        try check(!retainedNegative, "empty list never promotes a negative")
        let noTermsError = try Harness(terms: []) { _, _ in reply("") }
        let retainedError = await noTermsError.run()
        try check(!retainedError && noTermsError.callCount == 3, "empty list never bypasses model errors")
        let preview = try Harness(terms: [], preview: true) { _, _ in reply("political") }
        let previewMove = await preview.run()
        try check(!previewMove && (try preview.events.contains { $0.outcome == "previewPolitical" }), "preview still blocks Junk with no keywords")

        let context = LanguageModelSession.GenerationError.Context(debugDescription: "private-error-marker")
        let contextRecovery = try Harness { call, _ in
            if call == 1 { throw LanguageModelSession.GenerationError.exceededContextWindowSize(context) }
            return reply("political")
        }
        let longBody = String(repeating: "Example text about a campaign. ", count: 200)
        let contextMove = await contextRecovery.run(text: longBody)
        try check(contextMove && contextRecovery.callCount == 2, "context-limit failure can recover")
        try check(try contextRecovery.requestMetrics.contains { $0.maximumSectionCharacters == 3000 }
                  && contextRecovery.requestMetrics.contains { $0.maximumSectionCharacters == 1500 }, "context retry actually reduces section budget")
        for error in [LanguageModelSession.GenerationError.rateLimited(context), .decodingFailure(context), .concurrentRequests(context)] {
            let h = try Harness { call, _ in if call == 1 { throw error }; return reply("political") }
            let moved = await h.run()
            try check(moved && h.callCount == 2, "transient \(ModelFailureDetails.describe(error).category) recovers")
        }
        let unsupported = try Harness { _, _ in throw LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context) }
        let unsupportedMove = await unsupported.run()
        try check(!unsupportedMove && unsupported.callCount == 1, "unsupported language does not retry")

        let sections = try Harness { _, _ in reply("not-political") }
        let sectionMove = await sections.run(text: String(repeating: "A routine receipt and purchased items. ", count: 200))
        try check(!sectionMove && sections.callCount > 1, "negative requires every long-message section")
        let lateSectionError = try Harness { call, _ in reply(call == 1 ? "not-political" : "") }
        let partialMove = await lateSectionError.run(text: longBody)
        try check(!partialMove && (try lateSectionError.store.activity().processed == 0), "incomplete section coverage cannot become a final negative or move")

        var late: CheckedContinuation<PoliticalModel.Reply, Never>?
        let timed = try Harness(attemptSeconds: 0.03) { call, _ in
            if call == 1 { return await withCheckedContinuation { late = $0 } }
            return reply("not-political")
        }
        let timedMove = await timed.run()
        try check(!timedMove && timed.callCount == 2 && late != nil, "uncooperative first request times out and next attempt runs")
        late?.resume(returning: reply("political"))
        for _ in 0..<30 { await Task.yield() }
        try check(try timed.store.activity().junkRequested == 0 && !timed.store.protection.contains(messageID: "test@example.org"), "late positive cannot reserve Junk or overwrite the final negative")
        try check(try timed.events.contains { $0.outcome == "retryScheduled" && $0.category == "modelTimedOut" }, "attempt timeout is specifically reported")

        var abandoned: [CheckedContinuation<PoliticalModel.Reply, Never>] = []
        let overall = try Harness(attemptSeconds: 0.04, totalSeconds: 0.07) { _, _ in
            await withCheckedContinuation { abandoned.append($0) }
        }
        let began = ProcessInfo.processInfo.systemUptime
        let overallMove = await overall.run()
        try check(!overallMove && overall.callCount == 2 && ProcessInfo.processInfo.systemUptime - began < 1, "overall deadline includes all attempts")
        for continuation in abandoned { continuation.resume(returning: reply("political")) }
        for _ in 0..<30 { await Task.yield() }
        try check(try overall.store.activity().junkRequested == 0, "all late results after total deadline are discarded")

        for change in ["pause", "revision", "protection"] {
            var release: CheckedContinuation<PoliticalModel.Reply, Never>?
            let h = try Harness { _, _ in await withCheckedContinuation { release = $0 } }
            let task = Task { await h.run() }
            try await waitUntil { release != nil }
            if change == "pause" { try h.store.setPaused(true) }
            else if change == "revision" {
                var settings = try h.store.settings(); settings.revision = UUID().uuidString; try h.store.save(settings)
            } else { _ = try h.store.protection.reserve(messageID: "test@example.org") }
            release?.resume(returning: reply("political"))
            let moved = await task.value
            try check(!moved && (try h.store.activity().junkRequested == 0), "in-flight \(change) blocks final Junk intent")
        }

        let guards = try Harness(terms: []) { _, _ in reply("political") }
        try guards.store.setPaused(true)
        let pausedMove = await guards.run()
        try check(!pausedMove && guards.callCount == 0, "pause blocks model even with no keywords")
        try guards.store.setPaused(false)
        let selfMove = await guards.run(sender: "me@example.com")
        let otherMove = await guards.run(recipients: ["other@example.com"])
        try check(!selfMove && !otherMove && guards.callCount == 0, "empty list preserves self and selected-recipient guards")
        _ = try guards.store.protection.reserve(messageID: "restored@example.org")
        let protectedMove = await guards.run("restored@example.org")
        try check(!protectedMove && guards.callCount == 0, "restored mail remains protected without keywords")

        let ownMail = try Harness(allowOwnMail: true) { _, _ in reply("political") }
        let ownMailMove = await ownMail.run(sender: "My address <me@example.com>")
        let ownSettings = try ownMail.store.settings()
        let encodedOwn = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ownSettings)) as! [String: Any]
        try check(!NativeSettings().allowsOwnMailForTesting, "new settings protect self-mail by default")
        let crossSelfMove = await ownMail.run("cross-self@example.org", sender: "me@other.example")
        #if MAIL_FILTER_DEV
        try check(ownSettings.allowsOwnMailForTesting && encodedOwn["filterOwnMailForTesting"] as? Bool == true,
                  "Dev opt-in survives private settings round trip")
        try check(ownMailMove && crossSelfMove && ownMail.callCount == 2,
                  "Dev opt-in allows self-mail from selected or unchecked own accounts to request Junk")
        let restoredSelf = await ownMail.run(sender: "me@example.com")
        try check(!restoredSelf && ownMail.callCount == 2, "restored self-mail is protected even while Dev opt-in is on")
        let ownPreview = try Harness(preview: true, allowOwnMail: true) { _, _ in reply("political") }
        let ownPreviewMove = await ownPreview.run(sender: "me@example.com")
        try check(!ownPreviewMove && ownPreview.callCount == 1 && (try ownPreview.events.contains { $0.outcome == "previewPolitical" }),
                  "Dev self-mail opt-in retains Preview")
        let ownNegative = try Harness(allowOwnMail: true) { _, _ in reply("not-political") }
        let negativeSelfMove = await ownNegative.run(sender: "me@example.com")
        try check(!negativeSelfMove && ownNegative.callCount == 1, "Dev self-mail still needs a positive model label")
        let ownUnverified = try Harness(allowOwnMail: true) { _, _ in reply("political") }
        let unverifiedSelfMove = await ownUnverified.run(text: "An ordinary receipt.", sender: "me@example.com")
        try check(!unverifiedSelfMove && (try ownUnverified.events.contains { $0.category == "evidenceRejected" }),
                  "Dev self-mail retains keyword validation")
        let ownGuards = try Harness(allowOwnMail: true) { _, _ in reply("political") }
        let ownOtherRecipient = await ownGuards.run(sender: "me@example.com", recipients: ["unselected@example.org"])
        let ownEmpty = await ownGuards.run(text: " \n", sender: "me@example.com")
        try ownGuards.store.setPaused(true)
        let ownPaused = await ownGuards.run(sender: "me@example.com")
        try check(!ownOtherRecipient && !ownEmpty && !ownPaused && ownGuards.callCount == 0,
                  "Dev self-mail retains recipient, body and pause gates")
        var selfRelease: CheckedContinuation<PoliticalModel.Reply, Never>?
        let ownChanged = try Harness(allowOwnMail: true) { _, _ in await withCheckedContinuation { selfRelease = $0 } }
        let selfTask = Task { await ownChanged.run(sender: "me@example.com") }
        try await waitUntil { selfRelease != nil }
        var changed = try ownChanged.store.settings()
        changed.filterOwnMailForTesting = false
        changed.revision = UUID().uuidString
        try ownChanged.store.save(changed)
        selfRelease?.resume(returning: reply("political"))
        let changedSelfMove = await selfTask.value
        try check(!changedSelfMove && (try ownChanged.store.activity().junkRequested == 0),
                  "saving Dev opt-out during inference blocks final Junk intent")
        #else
        try check(!ownSettings.allowsOwnMailForTesting && encodedOwn["filterOwnMailForTesting"] == nil,
                  "production ignores and drops the Dev-only JSON setting")
        try check(!ownMailMove && !crossSelfMove && ownMail.callCount == 0,
                  "production protects self-mail from every own account even with an injected Dev flag")
        #endif

        var release: CheckedContinuation<PoliticalModel.Reply, Never>?
        let scheduler = InspectionScheduler(maximumPending: 2)
        let burst = try Harness(scheduler: scheduler) { call, _ in
            if call == 1 { return await withCheckedContinuation { release = $0 } }
            return reply("political")
        }
        let first = Task { await burst.run("one@example.org") }
        try await waitUntil { release != nil }
        let duplicate = await burst.run("one@example.org")
        let second = Task { await burst.run("two@example.org") }
        try await waitUntil { scheduler.pendingCount == 2 }
        let overflow = await burst.run("three@example.org")
        try check(!duplicate && !overflow && burst.callCount == 1, "burst serializes work and rejects duplicate/overflow without extra generation")
        release?.resume(returning: reply("political"))
        let firstMoved = await first.value, secondMoved = await second.value
        try check(firstMoved && secondMoved && burst.callCount == 2 && scheduler.pendingCount == 0, "queue drains and requests exactly two Junk intents")
        try check(try burst.store.activity().junkRequested == 2, "counter matches accepted actions after a burst")

        var cancelledRelease: CheckedContinuation<PoliticalModel.Reply, Never>?
        let cancelled = try Harness { _, _ in await withCheckedContinuation { cancelledRelease = $0 } }
        let task = Task { await cancelled.run() }
        try await waitUntil { cancelledRelease != nil }
        task.cancel()
        let cancelledMove = await task.value
        cancelledRelease?.resume(returning: reply("political"))
        for _ in 0..<30 { await Task.yield() }
        try check(!cancelledMove && (try cancelled.store.activity().junkRequested == 0), "parent cancellation plus late positive never requests Junk")
        #if MAIL_FILTER_DEV
        let variant = "Dev"
        #else
        let variant = "production"
        #endif
        print("Passed \(checks) \(variant) injected pipeline checks across \(scenarios) isolated scenarios; no real model, Mail access or message moves")
    }

}
