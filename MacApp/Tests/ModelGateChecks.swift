import Foundation

@main
@MainActor
struct ModelGateChecks {
    static var checks = 0
    static func expect(_ condition: Bool, _ name: String) throws {
        checks += 1
        if !condition { throw ToolError("Model gate check failed: " + name) }
    }
    static func ready(_ condition: () -> Bool) async throws {
        let until = ProcessInfo.processInfo.systemUptime + 2
        while !condition() {
            if ProcessInfo.processInfo.systemUptime > until { throw ToolError("Gate test did not synchronize") }
            await Task.yield()
        }
    }
    static func main() async throws {
        for _ in 0..<200 {
            let gate = ModelExecutionGate()
            var release: CheckedContinuation<Void, Never>?
            let owner = Task { try await gate.perform { await withCheckedContinuation { release = $0 } } }
            try await ready { release != nil }
            var ran = false
            let waiting = Task { try await gate.perform { ran = true } }
            try await ready { gate.waitingCount == 1 }
            // Cancellation races with handoff. The canceled waiter must never
            // invoke the SDK or consume an unreleased ownership slot.
            waiting.cancel(); release?.resume()
            _ = try await owner.value
            do { _ = try await waiting.value; throw ToolError("Canceled waiter ran") }
            catch is CancellationError { }
            try expect(!ran && !gate.isBusy && gate.waitingCount == 0, "cancel/handoff ownership")
        }
        let gate = ModelExecutionGate()
        var release: CheckedContinuation<Void, Never>?
        let owner = Task { try await gate.perform { await withCheckedContinuation { release = $0 } } }
        try await ready { release != nil }
        var order: [Int] = []
        let first = Task { try await gate.perform { order.append(1) } }
        try await ready { gate.waitingCount == 1 }
        let second = Task { try await gate.perform { order.append(2) } }
        try await ready { gate.waitingCount == 2 }
        owner.cancel()
        try expect(gate.isBusy && order.isEmpty, "active cancellation cannot release an unreturned call")
        release?.resume(); _ = try await owner.value; _ = try await first.value; _ = try await second.value
        try expect(order == [1, 2] && !gate.isBusy, "FIFO waiters drain after actual return")
        do { _ = try await gate.perform { throw ToolError("Expected test failure") } } catch { }
        let recovered = try await gate.perform { 42 }
        try expect(recovered == 42 && !gate.isBusy, "throwing call releases slot")

        var generation: CheckedContinuation<PoliticalModel.Reply, Never>?
        var countRan = false
        let raw = PoliticalModel.Engine(contextSize: 4096, estimatedTokens: false,
            instructionTokens: { _ in countRan = true; return 1 }, promptTokens: { _ in 1 },
            respond: { _, _, _ in await withCheckedContinuation { generation = $0 } })
        let engine = raw.serialized(using: gate)
        let response = Task { try await engine.respond("rules", "email", 64) }
        try await ready { generation != nil }
        let count = Task { try await engine.instructionTokens("rules") }
        try await ready { gate.waitingCount == 1 }
        try expect(!countRan, "tokenization cannot overlap an unreturned generation")
        generation?.resume(returning: .init(content: "not-political"))
        _ = try await response.value; _ = try await count.value
        try expect(countRan && !gate.isBusy, "tokenization resumes after generation")
        print("Passed \(checks) model-slot FIFO, error, cancellation/handoff and tokenization checks; no model or Mail calls.")
    }
}
