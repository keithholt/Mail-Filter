import Foundation

/// Bounded, serial inference admission with in-memory callback deduplication.
@MainActor
final class InspectionScheduler {
    enum Admission { case completed, duplicate, queueFull, cancelled }
    private let maximumPending: Int
    private let maximumRecent: Int
    private var busy = false
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    private var pending = Set<String>()
    private var completed = Set<String>()
    private var completionOrder: [String] = []
    var pendingCount: Int { pending.count }

    init(maximumPending: Int = 17, maximumRecent: Int = 1_024) {
        self.maximumPending = maximumPending
        self.maximumRecent = maximumRecent
    }

    func perform(fingerprint: String, operation: () async -> Bool) async -> Admission {
        guard !Task.isCancelled else { return .cancelled }
        guard !pending.contains(fingerprint), !completed.contains(fingerprint) else { return .duplicate }
        guard pending.count < maximumPending else { return .queueFull }
        pending.insert(fingerprint)
        defer { pending.remove(fingerprint) }
        if busy {
            let id = UUID()
            do {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                        else { waiters.append((id, continuation)) }
                    }
                } onCancel: {
                    Task { @MainActor in
                        if let index = self.waiters.firstIndex(where: { $0.0 == id }) {
                            self.waiters.remove(at: index).1.resume(throwing: CancellationError())
                        }
                    }
                }
            } catch { return .cancelled }
        }
        else { busy = true }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().1.resume() }
        }
        guard !Task.isCancelled else { return .cancelled }
        if await operation() {
            completed.insert(fingerprint)
            completionOrder.append(fingerprint)
            if completionOrder.count > maximumRecent { completed.remove(completionOrder.removeFirst()) }
        }
        return .completed
    }
}
