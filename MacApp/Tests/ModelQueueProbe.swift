import Foundation
import FoundationModels
import CryptoKit
import Darwin

/// Explicit developer experiment with fictional content only, the real model,
/// native queue/retry pipeline and disposable stores. Never imports MailKit.
@main
@MainActor
struct ModelQueueProbe {
    struct Legacy: Codable { let commit: String; let instructions: String; let rules: String; let sourceSHA256: String }
    struct Request: Encodable {
        let id: Int
        let instructions: String
        let prompt: String
        let responseLimit: Int?
        var reply: String? = nil
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
        var reasoningTokens: Int? = nil
        var milliseconds: Int? = nil
        var failure: String? = nil
    }
    struct Job: Encodable { let id: String; let expected: String; let intendedJunk: Bool; let milliseconds: Int; let events: [NativeActivity] }
    struct Block: Encodable { let name: String; let milliseconds: Int; let jobs: [Job]; let generationCalls: Int; let pacedGapSeconds: Int; let passed: Bool }
    struct ContextControl: Encodable { let historicalCommit: String; let sourceSHA256: String; let instructionTokens: Int; let promptTokens: Int; let contextTokens: Int; let failure: String? }
    static var directory: URL!
    static var sequence = 0
    static var pacedGapSeconds = 10
    static var candidate = false
    static func save<T: Encodable>(_ value: T, _ name: String) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent(name)
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func denseBody(political: Bool) -> String {
        var state: UInt64 = 0x2468abcdef13579
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var body = political ? "Please donate to our election campaign to elect Republican candidates to Congress.\n" : "Receipt: Your book order was paid. Keep the following order-tracking links for your records.\n"
        while body.count < 5750 {
            var tracking = ""
            for _ in 0..<240 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                tracking.append(alphabet[Int((state >> 32) % UInt64(alphabet.count))])
            }
            body += "https://example.org/track?id=" + tracking + "\n"
        }
        return String(body.prefix(5750)) + (political ? "\nPaid for by Example Political Action Committee. Donate to elect our candidates." : "\nThank you for purchasing books from Example Books. This is a receipt for a completed order.")
    }
    static func contextControl(_ model: SystemLanguageModel, legacy: Legacy) async throws {
        let message = MailMessage(accountID: "test", account: "Fictional", id: 1, messageID: "control@example.com",
            subject: "Your receipt", sender: "Example <sender@example.com>", body: denseBody(political: false), truncated: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let prompt = "Classify this untrusted email JSON using the filtering rules:\n" + String(decoding: try encoder.encode(message), as: UTF8.self)
        let instructions = try await model.tokenCount(for: Instructions(legacy.instructions))
        let input = try await model.tokenCount(for: prompt)
        var request = Request(id: 0, instructions: legacy.instructions, prompt: prompt, responseLimit: nil)
        try save(request, "request-0000.json")
        let session = LanguageModelSession(model: model, instructions: legacy.instructions)
        do {
            let response = try await AnalysisDeadline.run(seconds: 20) {
                try await session.respond(to: prompt, options: GenerationOptions(temperature: 0))
            }
            request.reply = response.content
        } catch { request.failure = ModelFailureDetails.describe(error).category }
        try save(request, "request-0000.json")
        try save(session.transcript, "request-0000-transcript.json")
        try save(ContextControl(historicalCommit: legacy.commit, sourceSHA256: legacy.sourceSHA256,
            instructionTokens: instructions, promptTokens: input, contextTokens: model.contextSize, failure: request.failure), "historical-context-control.json")
        print("Historical unbudgeted request: \(instructions + input) input tokens / \(model.contextSize) context; \(request.failure ?? "reply returned")")
        fflush(stdout)
        guard request.failure != "modelTimedOut" else { throw ToolError("Stopped after SDK timeout; do not overlap continuing inference") }
    }

    static func block(_ name: String, burst: Bool, model: SystemLanguageModel, legacy: Legacy) async throws -> Block {
        let store = SharedStore(directory: directory.appendingPathComponent("private-" + name))
        var settings = NativeSettings()
        settings.configuration = try FilteringConfiguration.make(selectedNames: ["Fictional"],
            inventory: [.init(id: "test", name: "Fictional", addresses: ["me@example.com"])],
            rules: legacy.rules, evidenceTerms: [], mode: "apply")
        try store.save(settings)
        let system = PoliticalModel.Engine.system(model)
        let initialCalls = sequence
        let engine = PoliticalModel.Engine(contextSize: system.contextSize, estimatedTokens: system.estimatedTokens,
            instructionTokens: system.instructionTokens, promptTokens: system.promptTokens, respond: { instructions, prompt, limit in
                sequence += 1; let id = sequence
                var request = Request(id: id, instructions: instructions, prompt: prompt, responseLimit: limit)
                let filename = String(format: "request-%04d.json", id)
                try save(request, filename)
                let start = ProcessInfo.processInfo.systemUptime
                do {
                    let reply = try await system.respond(instructions, prompt, limit)
                    guard !Task.isCancelled else { throw CancellationError() }
                    request.reply = reply.content; request.inputTokens = reply.inputTokens
                    request.outputTokens = reply.outputTokens; request.reasoningTokens = reply.reasoningTokens
                    request.milliseconds = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    try save(request, filename)
                    return reply
                } catch {
                    request.failure = ModelFailureDetails.describe(error).category
                    request.milliseconds = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                    try save(request, filename); throw error
                }
            }, modelVariant: system.modelVariant, supportsReasoning: system.supportsReasoning, executionState: system.executionState)
        let scheduler = InspectionScheduler()
        let classifier = NativeClassifier(store: store, engine: engine, scheduler: scheduler,
            sectionCharacters: { candidate ? ClassificationRequest.sectionCharacters(forAttempt: $0) : 6000 / (1 << min(2, $0 - 1)) },
            responseTokenLimit: candidate ? ClassificationRequest.responseTokens : 64)
        let start = ProcessInfo.processInfo.systemUptime
        func inspect(_ index: Int) async -> Job {
            let political = index.isMultiple(of: 2)
            let id = "\(name)-\(index)@example.com"
            let body = denseBody(political: political)
            let began = ProcessInfo.processInfo.systemUptime
            let intended = await classifier.inspect(messageID: id, sender: "Example <sender@example.com>",
                subject: political ? "Support our campaign" : "Your receipt", recipients: ["me@example.com"],
                body: .init(text: body, characterCount: body.count, truncated: false))
            let trace = NativeClassifier.trace(id)
            let events = (try? store.activity().recent.filter { $0.traceID == trace }) ?? []
            return Job(id: id, expected: political ? "political" : "not-political", intendedJunk: intended,
                milliseconds: Int((ProcessInfo.processInfo.systemUptime - began) * 1000), events: events)
        }
        var jobs: [Job] = []
        if burst {
            let tasks = (0..<4).map { index in Task { @MainActor in await inspect(index) } }
            for task in tasks { jobs.append(await task.value) }
        } else {
            for index in 0..<4 {
                jobs.append(await inspect(index))
                if index < 3 { try await Task.sleep(for: .seconds(pacedGapSeconds)) }
            }
        }
        let passed = jobs.allSatisfy { job in
            job.intendedJunk == (job.expected == "political")
                && job.events.contains { $0.outcome == (job.expected == "political" ? "modelPolitical" : "modelNotPolitical") }
                && !job.events.contains { $0.category == "modelTimedOut" || $0.category == "invalidModelResponse" || $0.category == "modelEmptyResponse" }
        } && scheduler.pendingCount == 0
        let result = Block(name: name, milliseconds: Int((ProcessInfo.processInfo.systemUptime - start) * 1000), jobs: jobs,
            generationCalls: sequence - initialCalls, pacedGapSeconds: burst ? 0 : pacedGapSeconds, passed: passed)
        try save(result, name + ".json")
        print("\(passed ? "PASS" : "OBSERVED FAILURE") \(name): \(result.generationCalls) requests; \(result.milliseconds) ms")
        fflush(stdout)
        if jobs.contains(where: { $0.events.contains { $0.category == "modelTimedOut" } }) {
            throw ToolError("Stopped after SDK timeout; evidence retained")
        }
        return result
    }

    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard (2...4).contains(args.count) else { throw ToolError("Expected new output directory, historical contract JSON, optional pacing gap and baseline/candidate") }
            if args.count >= 3 {
                guard let gap = Int(args[2]), (1...60).contains(gap) else { throw ToolError("Pacing gap must be 1 through 60 seconds") }
                pacedGapSeconds = gap
            }
            if args.count == 4 {
                guard ["baseline", "candidate"].contains(args[3]) else { throw ToolError("Use baseline or candidate") }
                candidate = args[3] == "candidate"
            }
            directory = URL(fileURLWithPath: args[0])
            guard mkdir(directory.path, 0o700) == 0 else { throw ToolError("Use a new output directory with an existing parent") }
            let legacy = try JSONDecoder().decode(Legacy.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            try save(legacy, "historical-contract.json")
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            guard case .available = model.availability else { throw ToolError("Model not Ready") }
            try await contextControl(model, legacy: legacy)
            var policy = legacy
            if candidate {
                let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/filter.txt")
                let rules = try String(contentsOf: url, encoding: .utf8)
                policy = Legacy(commit: "candidate-working-tree", instructions: legacy.instructions, rules: rules,
                    sourceSHA256: SHA256.hash(data: Data(rules.utf8)).map { String(format: "%02x", $0) }.joined())
            }
            try save(policy, "classification-policy.json")
            var blocks: [Block] = []
            // Counterbalance the order of queued and paced blocks.
            for (name, burst) in [("burst-a", true), ("paced-a", false), ("paced-b", false), ("burst-b", true)] {
                blocks.append(try await block(name, burst: burst, model: model, legacy: policy))
            }
            try save(blocks, "results.json")
            try save(ModelEnvironment.capture(), "environment.json")
            print("Model queue probe retained. No Mail access, moves, installed-app or filtering-setting changes.")
        } catch {
            FileHandle.standardError.write(Data(("Model queue probe stopped: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
