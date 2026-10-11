import Foundation

/// Bounds recent retry bookkeeping without stopping after a lifetime message cap.
final class BodyRequestTracker {
    private let lock = NSLock()
    private var requestedMessageIDs = Set<String>()
    private var requestOrder: [String] = []
    private let capacity: Int

    init(capacity: Int = 1_024) {
        self.capacity = capacity
    }

    func shouldRequestBody(messageID: String?, hasRawData: Bool) -> Bool {
        guard !hasRawData,
              let messageID = messageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageID.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard capacity > 0, !requestedMessageIDs.contains(messageID) else {
            return false
        }
        requestedMessageIDs.insert(messageID)
        requestOrder.append(messageID)
        if requestOrder.count > capacity { requestedMessageIDs.remove(requestOrder.removeFirst()) }
        return true
    }
}
