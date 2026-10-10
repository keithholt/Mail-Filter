import Foundation
import CryptoKit
import Darwin

// Kept results depend on content/rules. Junk move intent protects returned messages.
final class ProcessedMessages {
    private let url: URL
    private let lock: Int32
    private struct Saved: Codable {
        var kept: [String]
        var junk: [String]
    }
    private var keys: Set<String>
    private var junk: Set<String> = []
    private let rules: String

    init(path: String, rules: String) throws {
        url = URL(fileURLWithPath: path)
        self.rules = rules
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        lock = open(path + ".lock", O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw ToolError("Cannot open processed-message lock") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock)
            throw ToolError("Another filter run is already using the processed-message state")
        }
        do {
            if FileManager.default.fileExists(atPath: path) {
                let data = try Data(contentsOf: url)
                if let legacy = try? JSONDecoder().decode([String].self, from: data) {
                    keys = Set(legacy)
                } else {
                    let saved = try JSONDecoder().decode(Saved.self, from: data)
                    keys = Set(saved.kept)
                    junk = Set(saved.junk)
                }
            } else { keys = [] }
        } catch { close(lock); throw error }
    }

    deinit { close(lock) }

    func key(_ message: MailMessage) throws -> String {
        var data = Data(rules.utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        data.append(try encoder.encode(message))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func contains(_ message: MailMessage) throws -> Bool { keys.contains(try key(message)) }

    private func identity(_ message: MailMessage) throws -> String {
        guard !message.accountID.isEmpty, !message.messageID.isEmpty else {
            throw ToolError("Cannot persist Junk protection without stable message identity")
        }
        let data = try JSONEncoder().encode([message.accountID, message.messageID])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func protectsReturnedMessage(_ message: MailMessage) throws -> Bool {
        guard !message.accountID.isEmpty, !message.messageID.isEmpty else { return false }
        return junk.contains(try identity(message))
    }

    // Persist before touching Mail: a crash or ambiguous automation result must not
    // allow a returned message to be moved again. Failed attempts stay protected.
    func rememberJunkIntent(_ message: MailMessage) throws {
        junk.insert(try identity(message))
        try save()
    }

    private func save() throws {
        try JSONEncoder().encode(Saved(kept: keys.sorted(), junk: junk.sorted())).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func remember(_ message: MailMessage) throws {
        keys.insert(try key(message))
        try save()
    }
}
