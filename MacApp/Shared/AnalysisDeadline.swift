import Foundation

enum AnalysisDeadlineError: Error { case timedOut }

/// Return at the deadline even if generation ignores cancellation. Late results
/// never reach the caller, so they cannot trigger a delayed message action.
@MainActor
enum AnalysisDeadline {
    static func run<Value>(seconds: TimeInterval = 60,
                           operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let state = DeadlineResult<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let task = Task { @MainActor in
                    do {
                        try Task.checkCancellation()
                        state.finish(.success(try await operation()))
                    } catch { state.finish(.failure(error)) }
                }
                state.install(task)
                // asyncAfter's default timer leeway made a nominal 60-second
                // deadline return at about 63 seconds in full-duration tests.
                // This is one cancellable one-shot deadline, not a polling timer.
                let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .userInitiated))
                timer.setEventHandler { state.finish(.failure(AnalysisDeadlineError.timedOut)) }
                timer.schedule(deadline: .now() + max(seconds, 0), leeway: .milliseconds(10))
                state.install(timer)
                timer.resume()
            }
        } onCancel: { state.finish(.failure(CancellationError())) }
    }
}

private final class DeadlineResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var task: Task<Void, Never>?
    private var timer: DispatchSourceTimer?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result = completed { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func install(_ task: Task<Void, Never>) {
        lock.lock()
        if completed != nil { lock.unlock(); task.cancel() }
        else { self.task = task; lock.unlock() }
    }
    func install(_ timer: DispatchSourceTimer) {
        lock.lock()
        if completed != nil { lock.unlock(); timer.cancel() }
        else { self.timer = timer; lock.unlock() }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard completed == nil else { lock.unlock(); return }
        completed = result
        let continuation = self.continuation, task = self.task, timer = self.timer
        self.continuation = nil; self.task = nil; self.timer = nil
        lock.unlock()
        task?.cancel(); timer?.cancel()
        continuation?.resume(with: result)
    }
}
