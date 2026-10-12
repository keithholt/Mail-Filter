import Foundation

struct DeadlineCheckFailure: Error { let name: String }

@main
@MainActor
struct DeadlineChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw DeadlineCheckFailure(name: name) }
        count += 1
    }

    static func main() async throws {
        let result = try await AnalysisDeadline.run(seconds: 1) { 42 }
        try check(result == 42, "normal result preserved")
        do {
            let _: Int = try await AnalysisDeadline.run(seconds: 1) { throw DeadlineCheckFailure(name: "expected") }
            throw DeadlineCheckFailure(name: "operation failure was swallowed")
        } catch let error as DeadlineCheckFailure { try check(error.name == "expected", "operation failure preserved") }

        var hung: CheckedContinuation<Int, Never>?
        var lateAction = false
        do {
            let _: Int = try await AnalysisDeadline.run(seconds: 0.03) {
                await withCheckedContinuation { hung = $0 }
            }
            lateAction = true
            throw DeadlineCheckFailure(name: "uncooperative operation did not time out")
        } catch is AnalysisDeadlineError { try check(hung != nil, "deadline returns without waiting for cancellation acknowledgement") }
        hung?.resume(returning: 99)
        for _ in 0..<20 { await Task.yield() }
        try check(!lateAction, "late model output never reaches the message-action caller")

        let scheduler = InspectionScheduler()
        var blocked: CheckedContinuation<Int, Never>?
        _ = await scheduler.perform(fingerprint: "stalled") {
            do {
                let _: Int = try await AnalysisDeadline.run(seconds: 0.03) {
                    await withCheckedContinuation { blocked = $0 }
                }
            } catch { }
            return false
        }
        try check(scheduler.pendingCount == 0, "timed-out analysis releases the serial queue")
        var nextRan = false
        _ = await scheduler.perform(fingerprint: "next") { nextRan = true; return true }
        try check(nextRan, "subsequent mail can still be analyzed")
        blocked?.resume(returning: 0)

        var cancelledOperation: CheckedContinuation<Int, Never>?
        let task = Task { @MainActor in
            do {
                let _: Int = try await AnalysisDeadline.run(seconds: 5) {
                    await withCheckedContinuation { cancelledOperation = $0 }
                }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        while cancelledOperation == nil { await Task.yield() }
        task.cancel()
        let cancelled = await task.value
        try check(cancelled, "parent cancellation returns promptly")
        cancelledOperation?.resume(returning: 0)
        print("Passed \(count) generation deadline, late-result and queue-recovery checks; no model or Mail calls")
    }
}
