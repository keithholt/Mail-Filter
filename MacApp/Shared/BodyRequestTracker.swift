import Foundation

/// Bounds recent retry bookkeeping without stopping after a lifetime message cap.
final class BodyRequestTracker {
    private let lock = NSLock()
    private var requestedMessageIDs = Set<String>()
    private var requestOrder: [String] = []
    private var pendingSince: [String: TimeInterval] = [:]
    private let capacity: Int

    init(capacity: Int = 1_024) {
        self.capacity = capacity
    }

    func shouldRequestBody(messageID: String?, hasRawData: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard !hasRawData,
              let messageID = messageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageID.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard capacity > 0, !requestedMessageIDs.contains(messageID) else {
            return false
        }
        requestedMessageIDs.insert(messageID)
        pendingSince[messageID] = now
        requestOrder.append(messageID)
        if requestOrder.count > capacity {
            let oldest = requestOrder.removeFirst()
            requestedMessageIDs.remove(oldest)
            pendingSince.removeValue(forKey: oldest)
        }
        return true
    }

    func receivedBody(messageID: String?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int? {
        guard let messageID else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let start = pendingSince.removeValue(forKey: messageID.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Int(min(1_000_000_000, max(0, now - start) * 1000))
    }
}
