import Foundation

/// Bounded, serial inference admission with in-memory callback deduplication.
@MainActor
final class InspectionScheduler {
    enum Admission { case completed, duplicate, queueFull }
    private let maximumPending: Int
    private let maximumRecent: Int
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pending = Set<String>()
    private var completed = Set<String>()
    private var completionOrder: [String] = []
    var pendingCount: Int { pending.count }

    init(maximumPending: Int = 17, maximumRecent: Int = 1_024) {
        self.maximumPending = maximumPending
        self.maximumRecent = maximumRecent
    }

    func perform(fingerprint: String, operation: () async -> Bool) async -> Admission {
        guard !pending.contains(fingerprint), !completed.contains(fingerprint) else { return .duplicate }
        guard pending.count < maximumPending else { return .queueFull }
        pending.insert(fingerprint)
        defer { pending.remove(fingerprint) }
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }
        if await operation() {
            completed.insert(fingerprint)
            completionOrder.append(fingerprint)
            if completionOrder.count > maximumRecent { completed.remove(completionOrder.removeFirst()) }
        }
        return .completed
    }
}
