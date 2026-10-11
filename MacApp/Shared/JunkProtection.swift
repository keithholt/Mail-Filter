import Foundation
import CryptoKit
import Darwin

enum JunkProtectionError: Error { case invalidIdentity, invalidState, stateBusy, storageUnavailable }

enum JunkIdentity {
    static func canonical(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trimmed.hasPrefix("<") && trimmed.hasSuffix(">") ? String(trimmed.dropFirst().dropLast()) : trimmed
        guard !result.isEmpty, result.count <= 998, !result.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw JunkProtectionError.invalidIdentity
        }
        return result
    }

    static func hash(_ values: [String]) throws -> String {
        SHA256.hash(data: try JSONEncoder().encode(values)).map { String(format: "%02x", $0) }.joined()
    }

    // Account-independent: returning the same message to any Inbox stays protected.
    static func key(_ messageID: String) throws -> String { try hash(["mailkit-junk-v1", canonical(messageID)]) }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func protectedByCLI(messageID: String, accountIDs: [String], identities: [String]) throws -> Bool {
        let canonicalID = try canonical(messageID)
        // Mail's scripting property can omit the RFC header's surrounding brackets.
        let candidates = Set([messageID, messageID.trimmingCharacters(in: .whitespacesAndNewlines), canonicalID, "<" + canonicalID + ">"])
        let saved = Set(identities)
        for accountID in accountIDs {
            for candidate in candidates where saved.contains(try hash([accountID, candidate])) { return true }
        }
        return false
    }
}

/// Stores only hashes in the extension's sandbox. Every action is reserved on disk
/// before returning it to Mail; errors never reset protection or permit a move.
final class JunkProtection {
    private struct Saved: Codable { let schemaVersion: Int; let junk: [String] }
    private let url: URL
    private let maximumEntries = 100_000

    init(url: URL) { self.url = url }

    static func containerStore() throws -> JunkProtection {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw JunkProtectionError.storageUnavailable
        }
        return JunkProtection(url: root.appendingPathComponent("Mail-Filter/junk-protection.json"))
    }

    func contains(messageID: String) throws -> Bool {
        let key = try JunkIdentity.key(messageID)
        return try locked { try load().contains(key) }
    }

    /// False means another callback/process already reserved this message.
    func reserve(messageID: String) throws -> Bool {
        let key = try JunkIdentity.key(messageID)
        return try locked {
            var entries = try load()
            guard !entries.contains(key) else { return false }
            guard entries.count < maximumEntries else { throw JunkProtectionError.invalidState }
            entries.insert(key)
            try JSONEncoder().encode(Saved(schemaVersion: 1, junk: entries.sorted())).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        }
    }

    func importProtection(from source: URL) throws {
        let entries = try Self.readDigests(source)
        try locked {
            let merged = try load().union(entries)
            guard merged.count <= maximumEntries else { throw JunkProtectionError.invalidState }
            try JSONEncoder().encode(Saved(schemaVersion: 1, junk: merged.sorted())).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    static func readDigests(_ source: URL) throws -> Set<String> {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 16 * 1_024 * 1_024 else { throw JunkProtectionError.invalidState }
        let data = try Data(contentsOf: source)
        guard data.count <= 16 * 1_024 * 1_024 else { throw JunkProtectionError.invalidState }
        let saved = try JSONDecoder().decode(Saved.self, from: data)
        guard saved.schemaVersion == 1, saved.junk.count <= 100_000,
              saved.junk.allSatisfy(JunkIdentity.isDigest) else { throw JunkProtectionError.invalidState }
        return Set(saved.junk)
    }

    private func load() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Self.readDigests(url)
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw JunkProtectionError.storageUnavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw JunkProtectionError.stateBusy }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

/// The action gate is also exercised by synthetic tests. Preview never reserves
/// identity, and negatives/unverified positives can never request Junk.
struct JunkActionGate {
    static func shouldRequestJunk(decision: Classification.Decision, verifiedEvidence: String?, mode: String,
                                  messageID: String, protection: JunkProtection) throws -> Bool {
        guard mode == "apply", decision == .political, let evidence = verifiedEvidence, !evidence.isEmpty else { return false }
        return try protection.reserve(messageID: messageID)
    }
}
