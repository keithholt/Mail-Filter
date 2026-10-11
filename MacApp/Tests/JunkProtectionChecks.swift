import Foundation
import Darwin

struct ProtectionCheckFailure: Error { let name: String }

@main
struct JunkProtectionChecks {
    static var count = 0
    static func require(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !value() { throw ProtectionCheckFailure(name: name) }
        count += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        var failed = false
        do { try operation() } catch { failed = true }
        try require(failed, name)
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state/junk-protection.json")
        let store = JunkProtection(url: url)
        let id = "<campaign@example.org>"
        try require(try !store.contains(messageID: id), "new message initially unprotected")
        try require(try !JunkActionGate.shouldRequestJunk(decision: .political, verifiedEvidence: "election campaign", mode: "dry-run", messageID: id, protection: store), "preview never requests action")
        try require(try !store.contains(messageID: id), "preview does not poison future actual run")
        try require(try !JunkActionGate.shouldRequestJunk(decision: .notPolitical, verifiedEvidence: "election", mode: "apply", messageID: id, protection: store), "negative cannot move even with evidence")
        try require(try !JunkActionGate.shouldRequestJunk(decision: .political, verifiedEvidence: nil, mode: "apply", messageID: id, protection: store), "unverified positive cannot move")
        try require(try !JunkActionGate.shouldRequestJunk(decision: .political, verifiedEvidence: "", mode: "apply", messageID: id, protection: store), "empty evidence cannot move")
        try require(try JunkActionGate.shouldRequestJunk(decision: .political, verifiedEvidence: "election campaign", mode: "apply", messageID: id, protection: store), "verified apply reserves before requesting action")
        let reloaded = JunkProtection(url: url)
        try require(try reloaded.contains(messageID: "campaign@example.org"), "restart and bracket differences preserve protection")
        try require(try !reloaded.reserve(messageID: id), "restored message cannot move a second time")
        try require(try !JunkActionGate.shouldRequestJunk(decision: .political, verifiedEvidence: "different rule quote", mode: "apply", messageID: id, protection: reloaded), "changed prompt or evidence cannot remove restore protection")
        let savedText = try String(contentsOf: url, encoding: .utf8)
        try require(!savedText.contains("campaign@example.org") && !savedText.contains("election"), "state stores hashes rather than email content")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        try require(permissions?.intValue == 0o600, "saved state private permissions")
        let lock = open(url.path + ".lock", O_RDWR)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw ProtectionCheckFailure(name: "test lock unavailable") }
        try rejects("another process holding state prevents actions") { _ = try store.reserve(messageID: "other@example.org") }
        _ = flock(lock, LOCK_UN); close(lock)
        try require(try store.reserve(messageID: "other@example.org"), "lock release allows a later attempt")
        try rejects("missing identity cannot move") { _ = try store.reserve(messageID: " ") }
        try rejects("malformed identity cannot move") { _ = try store.reserve(messageID: "header\nvalue") }
        let cliHash = try JunkIdentity.hash(["example-account", "restored@example.org"])
        try require(try JunkIdentity.protectedByCLI(messageID: "<restored@example.org>", accountIDs: ["example-account", "other-account"], identities: [cliHash]), "CLI protection imported despite raw-header brackets")
        try require(try !JunkIdentity.protectedByCLI(messageID: "new@example.org", accountIDs: ["example-account"], identities: [cliHash]), "unrelated message remains eligible")
        let cliURL = root.appendingPathComponent("cli.json")
        try Data("{\"kept\":[],\"junk\":[\"\(cliHash)\"]}".utf8).write(to: cliURL)
        try require(try FilteringConfiguration.cliProtection(cliURL) == [cliHash], "exporter imports CLI move intent")
        try Data("[\"\(cliHash)\"]".utf8).write(to: cliURL)
        try require(try FilteringConfiguration.cliProtection(cliURL).isEmpty, "legacy kept-only CLI state does not create protection")
        try Data("corrupt".utf8).write(to: cliURL)
        try rejects("corrupt CLI state stops configuration") { _ = try FilteringConfiguration.cliProtection(cliURL) }
        try Data("corrupt".utf8).write(to: url)
        try rejects("corrupt persistent state prevents read") { _ = try store.contains(messageID: id) }
        try rejects("corrupt persistent state prevents reservation") { _ = try store.reserve(messageID: "new@example.org") }
        try require(try String(contentsOf: url, encoding: .utf8) == "corrupt", "corrupt state never silently reset")
        try Data("{\"schemaVersion\":2,\"junk\":[]}".utf8).write(to: url)
        try rejects("unsupported state version prevents action") { _ = try store.reserve(messageID: "new@example.org") }
        try Data("{\"schemaVersion\":1,\"junk\":[\"bad\"]}".utf8).write(to: url)
        try rejects("invalid protection digest prevents action") { _ = try store.reserve(messageID: "new@example.org") }
        let blocked = root.appendingPathComponent("file-not-directory")
        try Data("block".utf8).write(to: blocked)
        try rejects("inaccessible destination never permits move") {
            _ = try JunkActionGate.shouldRequestJunk(decision: .political, verifiedEvidence: "election", mode: "apply", messageID: id,
                                                   protection: JunkProtection(url: blocked.appendingPathComponent("state.json")))
        }
        print("Passed \(count) persistent recovery, preview and action-gating checks (temporary synthetic state; no Mail actions)")
    }
}
