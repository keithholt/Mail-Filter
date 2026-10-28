import Foundation
import FoundationModels
import CryptoKit
import Darwin

/// Developer-only, read-only replay. Exact private requests and responses stay in
/// an explicitly created directory; no Mail, shared store or action API is linked.
@MainActor
enum LocalModelReplay {
    struct Request: Codable {
        let instructions: String
        let prompt: String
        let instructionTokens: Int
        let promptTokens: Int
        let estimatedTokens: Bool
        let instructionsSHA256: String
        let promptSHA256: String
        init(instructions: String, prompt: String, instructionTokens: Int, promptTokens: Int, estimatedTokens: Bool) {
            self.instructions = instructions; self.prompt = prompt
            self.instructionTokens = instructionTokens; self.promptTokens = promptTokens
            self.estimatedTokens = estimatedTokens
            instructionsSHA256 = hash(Data(instructions.utf8)); promptSHA256 = hash(Data(prompt.utf8))
        }
    }
    struct Arm: Codable {
        let name: String
        let responseLimit: Int
        let maximumCharacters: Int
        let requests: [Request]
    }
    struct Fixture: Codable {
        let name: String
        let inputSHA256: String
        let expected: String?
        let arms: [Arm]
    }
    struct Scheduled: Codable, Equatable {
        let id: Int
        let repetition: Int
        let fixture: Int
        let arm: Int
    }
    struct Manifest: Encodable {
        let schemaVersion = 1
        let purpose = "Local read-only replay; no Mail access or action"
        let created = Date()
        let experiment: String
        let repetitions: Int
        let contextTokens: Int
        let requestDeadlineSeconds = 20
        let cancellationPolicy = "Stop the experiment after timeout; do not overlap potentially continuing inference"
        let environmentCapturePhase = "afterTrials"
        let policyOrigin: String
        let sourceSHA256: [String: String]
        let fixtures: [Fixture]
        let order: [Scheduled]
    }
    struct WireReply {
        let content: String
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
        var reasoningTokens: Int? = nil
        var transcriptJSON: String? = nil
    }
    struct SectionResult: Codable {
        let section: Int
        let instructionsSHA256: String
        let promptSHA256: String
        var status: String
        var thermalStateBefore = String(describing: ProcessInfo.processInfo.thermalState)
        var lowPowerModeBefore = ProcessInfo.processInfo.isLowPowerModeEnabled
        var elapsedMilliseconds = 0
        var content: String? = nil
        var responseUTF8Base64: String? = nil
        var responseScalars: [String]? = nil
        var legacyDecision: String? = nil
        var currentDecision: String? = nil
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
        var reasoningTokens: Int? = nil
        var transcriptJSON: String? = nil
        var errorDomain: String? = nil
        var errorCode: Int? = nil
    }
    struct Outcome: Codable {
        let trial: Scheduled
        let armName: String
        var status: String
        var decision: String? = nil
        var expected: String? = nil
        var sections: [SectionResult] = []
    }
    struct Event: Codable {
        let date: Date
        let trialID: Int
        let section: Int?
        let kind: String
        let status: String?
    }
    struct Options {
        var report: String?
        var synthetic = false
        var output: String?
        var experiment = "output-budget"
        var repetitions = 20
        var planOnly = false
        var originalPolicy: String?

        init(_ arguments: [String]) throws {
            var i = 0
            while i < arguments.count {
                let key = arguments[i]
                if key == "--synthetic-only" { synthetic = true }
                else if key == "--plan-only" { planOnly = true }
                else if ["--report", "--output", "--experiment", "--repetitions", "--original-policy"].contains(key) {
                    i += 1
                    guard i < arguments.count else { throw ToolError("Missing replay option value") }
                    let value = arguments[i]
                    switch key {
                    case "--report": report = value
                    case "--output": output = value
                    case "--experiment": experiment = value
                    case "--original-policy": originalPolicy = value
                    default:
                        guard let count = Int(value), (2...100).contains(count), count.isMultiple(of: 2) else {
                            throw ToolError("Replay repetitions must be an even number from 2 through 100")
                        }
                        repetitions = count
                    }
                } else { throw ToolError("Unknown replay option: \(key)") }
                i += 1
            }
            guard synthetic != (report != nil), output != nil,
                  ["output-budget", "section-size", "policy"].contains(experiment),
                  !(synthetic && originalPolicy != nil) else {
                throw ToolError("Use --replay-local (--synthetic-only | --report PATH) --output NEW_DIRECTORY [--experiment output-budget|section-size|policy] [--repetitions 20] [--original-policy PATH] [--plan-only]")
            }
        }
    }

    nonisolated static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func schedule(fixtures: Int, repetitions: Int) -> [Scheduled] {
        var result: [Scheduled] = []
        for repeatIndex in 0..<repetitions {
            // Each fixture has equally many AB and BA pairs. Rotate fixture order
            // too; do not always give one case the first request of every block.
            for offset in 0..<fixtures {
                let fixture = (repeatIndex + offset) % fixtures
                for arm in repeatIndex.isMultiple(of: 2) ? [0, 1] : [1, 0] {
                    result.append(Scheduled(id: result.count + 1, repetition: repeatIndex + 1, fixture: fixture, arm: arm))
                }
            }
        }
        return result
    }

    final class Journal {
        let directory: URL
        init(_ directory: URL) throws {
            self.directory = directory
            // Never overwrite another run or follow an existing output symlink.
            guard mkdir(directory.path, 0o700) == 0 else {
                throw ToolError("Replay needs a new output directory with an existing parent; no previous run was overwritten")
            }
        }
        func save<T: Encodable>(_ value: T, name: String) throws {
            let url = directory.appendingPathComponent(name)
            try encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        func event(_ kind: String, trial: Scheduled, section: Int? = nil, status: String? = nil) throws {
            let url = directory.appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw ToolError("Cannot create private replay journal")
                }
            }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: encode(Event(date: Date(), trialID: trial.id, section: section, kind: kind, status: status)) + Data([10]))
            try file.synchronize()
        }
    }

    static func plan(_ message: MailMessage, rules: String, characters: Int,
                     engine: PoliticalModel.Engine) async throws -> [Request] {
        var requests: [Request] = []
        // Use production planning/wrapping, but no inference. A scripted negative
        // visits every section rather than stopping at the first political reply.
        let capture = PoliticalModel.Engine(contextSize: engine.contextSize, estimatedTokens: engine.estimatedTokens,
            instructionTokens: engine.instructionTokens, promptTokens: engine.promptTokens,
            respond: { instructions, prompt, _ in
                requests.append(Request(instructions: instructions, prompt: prompt,
                    instructionTokens: try await engine.instructionTokens(instructions),
                    promptTokens: try await engine.promptTokens(prompt), estimatedTokens: engine.estimatedTokens))
                return PoliticalModel.Reply(content: "not-political")
            })
        _ = try await PoliticalModel.classify(message, rules: rules, engine: capture,
            maximumCharacters: characters, responseTokenLimit: 64)
        return requests
    }

    static func execute(_ trial: Scheduled, fixture: Fixture, context: Int, journal: Journal,
                        generate: (Request, Int, Int) async throws -> WireReply) async throws -> Outcome {
        let arm = fixture.arms[trial.arm]
        var outcome = Outcome(trial: trial, armName: arm.name, status: "started", expected: fixture.expected)
        try journal.event("trialStarted", trial: trial)
        for (offset, request) in arm.requests.enumerated() {
            let section = offset + 1
            var result = SectionResult(section: section, instructionsSHA256: request.instructionsSHA256,
                promptSHA256: request.promptSHA256, status: "started")
            if request.instructionTokens + request.promptTokens + arm.responseLimit + ClassificationRequest.framingTokens > context {
                result.status = "skippedUnchangedRequestExceedsBudget"
                outcome.sections.append(result); outcome.status = result.status
                break
            }
            try journal.event("sectionStarted", trial: trial, section: section)
            let start = ProcessInfo.processInfo.systemUptime
            do {
                let reply = try await generate(request, arm.responseLimit, section)
                result.content = reply.content
                result.responseUTF8Base64 = Data(reply.content.utf8).base64EncodedString()
                result.responseScalars = reply.content.unicodeScalars.map { String(format: "U+%04X", $0.value) }
                result.legacyDecision = ModelProbe.legacyLabel(reply.content)?.rawValue
                result.inputTokens = reply.inputTokens; result.outputTokens = reply.outputTokens
                result.reasoningTokens = reply.reasoningTokens; result.transcriptJSON = reply.transcriptJSON
                do {
                    result.currentDecision = try parsePoliticalLabel(reply.content).rawValue
                    result.status = "validLabel"
                } catch { result.status = ModelFailureDetails.describe(error).category }
            } catch {
                let details = ModelFailureDetails.describe(error)
                result.status = details.category; result.errorDomain = details.domain; result.errorCode = details.code
            }
            result.elapsedMilliseconds = Int(max(0, ProcessInfo.processInfo.systemUptime - start) * 1000)
            outcome.sections.append(result)
            // Commit the complete raw evidence for each finished section before
            // beginning another request. A later stall cannot erase it.
            try journal.save(outcome, name: String(format: "trial-%04d.json", trial.id))
            try journal.event("sectionFinished", trial: trial, section: section, status: result.status)
            guard result.currentDecision != nil else { outcome.status = result.status; break }
            if result.currentDecision == "political" { outcome.decision = "political"; break }
            if section == arm.requests.count { outcome.decision = "not-political" }
        }
        if outcome.decision != nil { outcome.status = "completed" }
        try journal.save(outcome, name: String(format: "trial-%04d.json", trial.id))
        try journal.event("trialFinished", trial: trial, status: outcome.status)
        return outcome
    }

    static func run(_ arguments: [String]) async throws {
        let options = try Options(arguments)
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else { throw ToolError("Model unavailable; replay not started") }
        let engine = PoliticalModel.Engine.system(model)
        let root = URL(fileURLWithPath: defaultConfigurationPath("prompts/filter.txt")).deletingLastPathComponent().deletingLastPathComponent()
        var fixtures: [Fixture] = []
        var inputs: [(String, Data, MailMessage, String, String?)] = []
        if let path = options.report {
            let url = URL(fileURLWithPath: path)
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else { throw ToolError("Oversized diagnostic export") }
            let data = try Data(contentsOf: url)
            let input = try JSONDecoder().decode(ModelProbe.Input.self, from: data)
            guard let body = input.extractedBody, let policy = input.currentPolicy, body.count <= 6000,
                  input.subject.count <= 500, input.sender.count <= 500, policy.rules.count <= 32_000 else {
                throw ToolError("Export has no valid bounded model input")
            }
            inputs.append(("selected-email", data, MailMessage(accountID: "fixture", account: "Fixture", id: 1,
                messageID: "replay@example.com", subject: input.subject, sender: input.sender, body: body, truncated: false), policy.rules, nil))
        } else {
            let rules = try String(contentsOfFile: defaultConfigurationPath("prompts/filter.txt"), encoding: .utf8)
            let padding = String(String(repeating: "Friend, please read this note before deciding how to respond. Our deadline is tonight.\n", count: 90).prefix(5300))
            for (name, subject, body, expected) in [
                ("forwarded-appeal", "Fwd: This is the hardest email I've had to write", padding + "\nDonate to elect Republican candidates to Congress. Paid for by Example Political Action Committee.", "political"),
                ("forwarded-receipt", "Fwd: Your receipt", String(String(repeating: "Order 123: books and stationery. Your payment was received. Keep this receipt.\n", count: 90).prefix(5600)), "not-political")
            ] {
                let message = MailMessage(accountID: "fixture", account: "Fixture", id: 1, messageID: "replay@example.com",
                    subject: subject, sender: "Example <sender@example.com>", body: body, truncated: false)
                inputs.append((name, try encode(["subject": subject, "sender": message.sender, "body": body, "rules": rules]), message, rules, expected))
            }
        }
        let original = try options.originalPolicy.map { try String(contentsOfFile: $0, encoding: .utf8) }
        guard original == nil || original!.count <= 32_000 else { throw ToolError("Oversized original policy") }
        for (name, data, message, savedRules, expected) in inputs {
            let oldRules = original ?? ModelProbe.previousPolicy(savedRules)
            let baseline = try await plan(message, rules: oldRules, characters: 6000, engine: engine)
            let second: [Request]
            switch options.experiment {
            case "section-size": second = try await plan(message, rules: oldRules, characters: 3000, engine: engine)
            case "policy": second = try await plan(message, rules: savedRules, characters: 6000, engine: engine)
            default: second = baseline // Byte-identical input at both output caps.
            }
            fixtures.append(Fixture(name: name, inputSHA256: hash(data), expected: expected, arms: [
                Arm(name: "baseline-6000-64", responseLimit: 64, maximumCharacters: 6000, requests: baseline),
                Arm(name: options.experiment, responseLimit: options.experiment == "output-budget" ? 256 : 64,
                    maximumCharacters: options.experiment == "section-size" ? 3000 : 6000, requests: second)
            ]))
        }
        let journal = try Journal(URL(fileURLWithPath: options.output!))
        var fingerprints: [String: String] = [:]
        for path in ["Sources/MailFilter/PoliticalModel.swift", "Sources/MailFilter/ClassificationRequest.swift",
                     "Sources/MailFilter/Core.swift", "MacApp/ModelProbe.swift", "MacApp/LocalModelReplay.swift",
                     "MacApp/Shared/AnalysisDeadline.swift", "MacApp/Shared/ModelEnvironment.swift"] {
            fingerprints[path] = hash(try Data(contentsOf: root.appendingPathComponent(path)))
        }
        let order = schedule(fixtures: fixtures.count, repetitions: options.repetitions)
        try journal.save(Manifest(experiment: options.experiment, repetitions: options.repetitions, contextTokens: model.contextSize,
            policyOrigin: original == nil ? "Previous standard ending reconstructed; custom policy is not a proven build-18 snapshot" : "Explicit original-policy snapshot",
            sourceSHA256: fingerprints, fixtures: fixtures, order: order), name: "manifest.json")
        print("Private replay directory: \(journal.directory.path)")
        if options.planOnly { print("Frozen plan saved; no generation, Mail access or settings changes."); return }
        var results: [Outcome] = []
        for trial in order {
            let outcome = try await execute(trial, fixture: fixtures[trial.fixture], context: model.contextSize, journal: journal) { request, limit, section in
                let session = LanguageModelSession(model: model, instructions: request.instructions)
                let pending = String(format: "trial-%04d-section-%02d-transcript.json", trial.id, section)
                try journal.save(session.transcript, name: pending)
                // Save transcript even on a framework error or cancellation.
                defer { try? journal.save(session.transcript, name: pending) }
                let response = try await AnalysisDeadline.run(seconds: 20) {
                    try await session.respond(to: request.prompt,
                        options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: limit))
                }
                var value = WireReply(content: response.content,
                    transcriptJSON: String(decoding: try encode(session.transcript), as: UTF8.self))
                if #available(macOS 27.0, *) {
                    value.inputTokens = response.usage.input.totalTokenCount
                    value.outputTokens = response.usage.output.totalTokenCount
                    value.reasoningTokens = response.usage.output.reasoningTokenCount
                }
                return value
            }
            results.append(outcome)
            print("Trial \(trial.id)/\(order.count): \(outcome.armName) — \(outcome.decision ?? outcome.status)")
            // A non-cooperative inference may continue in Apple's service after
            // cancellation. Stop this experiment rather than overlap its trials.
            if ["modelTimedOut", "analysisCancelled"].contains(outcome.status) {
                print("Replay stopped after timeout/cancellation; earlier evidence is retained.")
                break
            }
        }
        try journal.save(EnvironmentReport(environment: ModelEnvironment.capture(), plannedTrials: order.count, outcomes: results), name: "results.json")
        print("Replay ended: \(results.count)/\(order.count) trials retained. No Mail access, moves or settings changes.")
    }
    struct EnvironmentReport: Encodable { let environment: ModelEnvironment; let plannedTrials: Int; let outcomes: [Outcome] }

    static func check() async throws {
        var assertions = 0
        func expect(_ condition: Bool) throws { assertions += 1; if !condition { throw ToolError("Replay check \(assertions) failed") } }
        let order = schedule(fixtures: 2, repetitions: 20)
        try expect(order.count == 80 && Set(order.map(\.id)).count == 80)
        for fixture in 0..<2 {
            let rows = order.filter { $0.fixture == fixture }
            try expect(rows.filter { $0.arm == 0 }.count == 20 && rows.filter { $0.arm == 1 }.count == 20)
            try expect(stride(from: 0, to: rows.count, by: 2).filter { rows[$0].arm == 0 }.count == 10)
        }
        try expect(order == schedule(fixtures: 2, repetitions: 20))
        try expect(hash(Data("political".utf8)) != hash(Data("political\n".utf8)))
        for arguments in [[], ["--synthetic-only", "--report", "x", "--output", "x"],
                          ["--synthetic-only", "--output", "x", "--repetitions", "3"]] {
            var refused = false
            do { _ = try Options(arguments) } catch { refused = true }
            try expect(refused)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mail-filter-replay-check-" + UUID().uuidString)
        let journal = try Journal(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var refusedExisting = false
        do { _ = try Journal(directory) } catch { refusedExisting = true }
        try expect(refusedExisting)
        let request = Request(instructions: "rules", prompt: "email", instructionTokens: 10, promptTokens: 20, estimatedTokens: false)
        let fixture = Fixture(name: "check", inputSHA256: "test", expected: "political", arms: [
            Arm(name: "a", responseLimit: 64, maximumCharacters: 6000, requests: [request]),
            Arm(name: "b", responseLimit: 256, maximumCharacters: 6000, requests: [request])])
        var calls = 0
        let result = try await execute(order[0], fixture: fixture, context: 4096, journal: journal) { _, _, _ in
            calls += 1; return WireReply(content: "\u{FEFF}political")
        }
        try expect(calls == 1 && result.decision == "political" && result.sections[0].legacyDecision == nil)
        try expect(result.sections[0].responseUTF8Base64 == Data("\u{FEFF}political".utf8).base64EncodedString())
        let rejected = try await execute(order[1], fixture: fixture, context: 4096, journal: journal) { _, _, _ in WireReply(content: "") }
        try expect(rejected.decision == nil && rejected.status == "modelEmptyResponse")
        let skipped = try await execute(order[2], fixture: fixture, context: 32, journal: journal) { _, _, _ in
            calls += 1; return WireReply(content: "political")
        }
        try expect(calls == 1 && skipped.status == "skippedUnchangedRequestExceedsBudget")
        let events = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
        try expect(events.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 10)
        for name in ["events.jsonl", "trial-0001.json", "trial-0002.json", "trial-0003.json"] {
            let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.posixPermissions] as? Int
            try expect(mode == 0o600)
        }
        try expect(fixture.arms[0].requests[0].promptSHA256 == fixture.arms[1].requests[0].promptSHA256)
        let fake = PoliticalModel.Engine(contextSize: 4096, estimatedTokens: false,
            instructionTokens: { _ in 100 }, promptTokens: { _ in 100 }, respond: { _, _, _ in
                throw ToolError("Planning must never call the supplied inference transport")
            })
        let message = MailMessage(accountID: "fixture", account: "Fixture", id: 1, messageID: "test@example.com",
            subject: "Test", sender: "Example <sender@example.com>", body: String(repeating: "word ", count: 1100), truncated: false)
        let long = try await plan(message, rules: "Classify political mail", characters: 6000, engine: fake)
        let short = try await plan(message, rules: "Classify political mail", characters: 3000, engine: fake)
        try expect(long.count == 1 && short.count == 2)
        try expect(long[0].instructionsSHA256 == short[0].instructionsSHA256)
        try expect(short[0].prompt.contains("openingContext") && short[1].prompt.contains("closingContext"))
        let split = Fixture(name: "split", inputSHA256: "test", expected: "not-political", arms: [
            Arm(name: "split", responseLimit: 64, maximumCharacters: 3000, requests: short)])
        let splitTrial = Scheduled(id: 4, repetition: 1, fixture: 0, arm: 0)
        var visited: [Int] = []
        let incomplete = try await execute(splitTrial, fixture: split, context: 4096, journal: journal) { _, _, section in
            visited.append(section)
            return WireReply(content: section == 1 ? "not-political" : "")
        }
        try expect(visited == [1, 2] && incomplete.decision == nil && incomplete.sections.count == 2)
        let retained = try JSONDecoder().decode(Outcome.self, from: Data(contentsOf: directory.appendingPathComponent("trial-0001.json")))
        try expect(retained.sections[0].responseUTF8Base64 == result.sections[0].responseUTF8Base64)
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        try expect(mode == 0o700)
        let pendingTrial = Scheduled(id: 5, repetition: 1, fixture: 0, arm: 0)
        var startedBeforeGeneration = false
        let timedOut = try await execute(pendingTrial, fixture: fixture, context: 4096, journal: journal) { _, _, _ in
            let saved = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
            startedBeforeGeneration = saved.contains("\"kind\":\"sectionStarted\"") && saved.contains("\"trialID\":5")
            throw AnalysisDeadlineError.timedOut
        }
        try expect(startedBeforeGeneration && timedOut.status == "modelTimedOut" && timedOut.decision == nil)
        let encoded = try encode(request)
        try expect(String(decoding: encoded, as: UTF8.self).contains(request.instructionsSHA256))
        try expect(try JSONDecoder().decode(Request.self, from: encoded).promptSHA256 == request.promptSHA256)
        print("Passed \(assertions) local replay checks; no model generation or Mail access.")
    }
}
