import Foundation
import FoundationModels
import CryptoKit

/// The native request/retry/scheduler/action-gate pipeline with disposable stores.
/// A full run uses real production deadlines/delays. No Mail API is linked.
@main
@MainActor
struct TimingQualification {
    struct Event: Codable { let name: String; let milliseconds: Int; let active: Int }
    struct Result: Codable {
        let name: String
        let milliseconds: Int
        let peakSDKCalls: Int
        let calls: Int
        let intendedJunkActions: Int
        let passed: Bool
        let checks: [String: Bool]
        let nativeEvents: [NativeActivity]
        let events: [Event]
    }
    struct Report: Encodable {
        let date = Date()
        let fullDuration: Bool
        let results: [Result]
    }
    @MainActor final class Trace {
        let start = ProcessInfo.processInfo.systemUptime
        var active = 0, peak = 0, calls = 0
        var events: [Event] = []
        var elapsed: Double { ProcessInfo.processInfo.systemUptime - start }
        func event(_ name: String) { events.append(Event(name: name, milliseconds: Int(elapsed * 1000), active: active)) }
    }
    static var scale = 1.0
    static var results: [Result] = []
    static var output: URL!
    static var root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-filter-timing-" + UUID().uuidString)

    // Deliberately ignores Task cancellation, like an uncooperative SDK call.
    static func uncooperative(_ seconds: Double) async {
        await withCheckedContinuation { continuation in
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .userInitiated))
            timer.setEventHandler { timer.setEventHandler(handler: nil); timer.cancel(); continuation.resume() }
            timer.schedule(deadline: .now() + seconds * scale, leeway: .nanoseconds(0))
            timer.resume()
        }
    }
    static func waitUntil(_ condition: () -> Bool, seconds: Double = 70) async throws {
        let until = ProcessInfo.processInfo.systemUptime + seconds * scale + 1
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < until else { throw ToolError("Timing test synchronization failed") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @MainActor final class Harness {
        let trace = Trace()
        let store: SharedStore
        let classifier: NativeClassifier
        let scheduler = InspectionScheduler()
        init(name: String, gated: Bool, firstSectionLimit: Int = 6000, script: @escaping (Int) async throws -> String) throws {
            store = SharedStore(directory: root.appendingPathComponent(name))
            var settings = NativeSettings()
            settings.configuration = try FilteringConfiguration.make(selectedNames: ["Test"],
                inventory: [.init(id: "test", name: "Test", addresses: ["me@example.com"])],
                rules: "Classify political campaign appeals; keep receipts.", evidenceTerms: [], mode: "apply")
            try store.save(settings)
            let trace = self.trace
            let raw = PoliticalModel.Engine(contextSize: 4096, estimatedTokens: false,
                instructionTokens: { _ in 100 }, promptTokens: { _ in 100 }, respond: { _, _, _ in
                    trace.calls += 1; let call = trace.calls
                    trace.active += 1; trace.peak = max(trace.peak, trace.active); trace.event("sdkStarted-\(call)")
                    defer { trace.active -= 1; trace.event("sdkReturned-\(call)") }
                    return PoliticalModel.Reply(content: try await script(call))
                })
            classifier = NativeClassifier(store: store, engine: gated ? raw.serialized(using: ModelExecutionGate()) : raw,
                scheduler: scheduler, attemptSeconds: 20 * scale, totalSeconds: 60 * scale,
                sectionCharacters: { max(1500, firstSectionLimit / (1 << min(2, $0 - 1))) }, responseTokenLimit: 64,
                retryDelay: { attempt in try await Task.sleep(for: .seconds(Double(attempt) * scale)) })
        }
        func run(_ id: String = "first", long: Bool = false) async -> Bool {
            trace.event("jobSubmitted-" + id)
            let body = long ? String(repeating: "A routine receipt for your order. ", count: 210) : "Please support our campaign."
            let outcome = await classifier.inspect(messageID: id + "@example.com", sender: "outside@example.org",
                subject: "Timing fixture", recipients: ["me@example.com"],
                body: .init(text: body, characterCount: body.count, truncated: false))
            trace.event("jobReturned-" + id)
            return outcome
        }
    }
    static func retain(_ h: Harness, name: String, passed: Bool, checks: [String: Bool] = [:]) throws {
        let activity = try h.store.activity()
        results.append(Result(name: name, milliseconds: Int(h.trace.elapsed * 1000), peakSDKCalls: h.trace.peak,
            calls: h.trace.calls, intendedJunkActions: activity.junkRequested, passed: passed, checks: checks,
            nativeEvents: activity.recent, events: h.trace.events))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Report(fullDuration: scale == 1, results: results)).write(to: output, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        print("\(passed ? "PASS" : "FAIL") \(name): \(Int(h.trace.elapsed * 1000)) ms; peak SDK calls \(h.trace.peak)")
        fflush(stdout)
        guard passed else { throw ToolError("Timing qualification failed: " + name) }
    }

    static func overlap(gated: Bool) async throws {
        let name = gated ? "gated-timeout-then-queued-peer" : "legacy-timeout-overlap-reproduction"
        let h = try Harness(name: name, gated: gated) { call in
            if call == 1 { await uncooperative(23); return "political" }
            return "not-political"
        }
        let first = Task { await h.run() }
        try await waitUntil { h.trace.calls == 1 }
        let peer = Task { await h.run("peer") }
        let firstMoved = await first.value, peerMoved = await peer.value
        h.trace.event("bothLogicalJobsReturned")
        try await waitUntil { h.trace.active == 0 }
        let expectedPeak = gated ? 1 : 2
        let activity = try h.store.activity()
        let passed = !firstMoved && !peerMoved && h.trace.peak == expectedPeak && h.trace.calls == 3
            && h.scheduler.pendingCount == 0 && activity.junkRequested == 0
        try retain(h, name: name, passed: passed)
    }

    static func boundary(seconds: Double) async throws {
        let before = seconds < 20
        let name = before ? "response-before-real-attempt-deadline" : "late-positive-after-real-attempt-deadline"
        let h = try Harness(name: name, gated: true) { call in
            // Keep I/O jitter from consuming a tiny accelerated boundary margin.
            // The full-duration qualification uses exactly 19 / 20.5 seconds.
            if call == 1 { await uncooperative(scale == 1 ? seconds : (before ? 15 : 22)); return before ? "not-political" : "political" }
            return "not-political"
        }
        let moved = await h.run()
        try await waitUntil { h.trace.active == 0 }
        let elapsed = h.trace.elapsed / scale
        let activity = try h.store.activity()
        let passed = !moved && h.trace.calls == (before ? 1 : 2) && h.trace.peak == 1
            && elapsed >= (scale == 1 ? (before ? 18.5 : 20.5) : (before ? 14 : 20)) && elapsed < (scale == 1 ? 24 : 40)
            && activity.junkRequested == 0
            && (before || activity.recent.contains { $0.outcome == "retryScheduled" && $0.category == "modelTimedOut" })
        try retain(h, name: name, passed: passed)
    }

    static func slowSections() async throws {
        let h = try Harness(name: "multi-section-total-budget", gated: true, firstSectionLimit: 3000) { _ in
            await uncooperative(6); return "not-political"
        }
        let first = Task { await h.run(long: true) }
        try await waitUntil { h.trace.calls > 0 }
        let peer = Task { await h.run("queued-peer") }
        let moved = await first.value
        let firstFinished = h.trace.elapsed / scale
        let peerMoved = await peer.value
        try await waitUntil { h.trace.active == 0 }
        let activity = try h.store.activity()
        let firstTrace = NativeClassifier.trace("first@example.com")
        let firstEvents = activity.recent.filter { $0.traceID == firstTrace }
        let startedAttempts = Set(firstEvents.filter { $0.outcome == "analysisStarted" }.compactMap(\.attempt))
        let checks = ["noMove": !moved && !peerMoved, "oneAwaitedSDKCall": h.trace.peak == 1,
            "threeAttempts": startedAttempts == [1, 2, 3],
            "overallDeadline": firstFinished >= 59 && firstFinished < (scale == 1 ? 61.5 : 80),
            "timeoutRecorded": firstEvents.contains { $0.category == "modelTimedOut" },
            "incompleteCoverageNotNegative": !firstEvents.contains { $0.outcome == "notPolitical" || $0.outcome == "junkRequested" },
            "peerDrained": h.scheduler.pendingCount == 0]
        try retain(h, name: "multi-section-20-second-attempts-60-second-total-and-peer-recovery",
            passed: checks.values.allSatisfy { $0 }, checks: checks)
    }

    static func cancelledWaiters() async throws {
        let h = try Harness(name: "cancelled-queued-job", gated: true) { _ in "not-political" }
        var release: CheckedContinuation<Void, Never>?
        let first = Task { await h.scheduler.perform(fingerprint: "held") {
            await withCheckedContinuation { release = $0 }; return true
        } }
        try await waitUntil { release != nil }
        var executed = false
        let queued = Task { await h.scheduler.perform(fingerprint: "cancelled") { executed = true; return true } }
        try await waitUntil { h.scheduler.pendingCount == 2 }
        queued.cancel()
        let admission = try await AnalysisDeadline.run(seconds: 1) { await queued.value }
        let removedPromptly = h.scheduler.pendingCount == 1
        release?.resume(); _ = await first.value
        try retain(h, name: "queued-cancellation-does-not-wait-for-active-model", passed: admission == .cancelled && !executed && removedPromptly && h.scheduler.pendingCount == 0)

        let gate = ModelExecutionGate()
        var releaseGate: CheckedContinuation<Void, Never>?
        let owner = Task { try await gate.perform { await withCheckedContinuation { releaseGate = $0 } } }
        try await waitUntil { releaseGate != nil }
        let waiter = Task { try await gate.perform { throw ToolError("Cancelled model waiter executed") } }
        try await waitUntil { gate.waitingCount == 1 }
        waiter.cancel()
        do { _ = try await AnalysisDeadline.run(seconds: 1) { try await waiter.value }; throw ToolError("Cancelled waiter succeeded") }
        catch is CancellationError { }
        guard gate.waitingCount == 0 && gate.isBusy else { throw ToolError("Model waiter lost active ownership") }
        releaseGate?.resume(); _ = try await owner.value
        guard !gate.isBusy else { throw ToolError("Model slot was not released") }
    }

    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 3, ["--full", "--quick"].contains(args[0]), args[1] == "--output" else {
                throw ToolError("Use --full|--quick --output NEW_REPORT.json")
            }
            scale = args[0] == "--full" ? 1 : 0.02
            output = URL(fileURLWithPath: args[2])
            guard !FileManager.default.fileExists(atPath: output.path) else { throw ToolError("Refusing to overwrite timing evidence") }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            print("\(scale == 1 ? "Full-duration" : "Accelerated") timing qualification; scripted SDK, real native pipeline; no Mail access or moves.")
            fflush(stdout)
            try await overlap(gated: false)
            try await overlap(gated: true)
            try await boundary(seconds: 19)
            try await boundary(seconds: 20.5)
            try await slowSections()
            try await cancelledWaiters()
            print("Timing qualification passed. Evidence: " + output.path)
        } catch {
            FileHandle.standardError.write(Data(("Timing qualification failed: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
