import Foundation
import AppKit
import Darwin

@main
@MainActor
struct StoreReadinessChecks {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try value() else { throw ToolError(name) }
        count += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { count += 1; return }
        throw ToolError(name)
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("store-readiness-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let groups = try NativeAccount.manualGroups("OWNER@example.com, alias@example.com\nother@example.net")
        try check(groups.count == 2 && groups[0].addresses == ["owner@example.com", "alias@example.com"], "manual groups normalize aliases")
        try check(groups[0].id.hasPrefix("manual-") && groups[0].id == NativeAccount.manualGroups("alias@example.com, owner@example.com")[0].id, "manual IDs are stable without imitating Mail IDs")
        try rejects("duplicate addresses rejected") { _ = try NativeAccount.manualGroups("owner@example.com\nowner@example.com") }
        try rejects("empty alias rejected") { _ = try NativeAccount.manualGroups("owner@example.com,") }
        try rejects("invalid address rejected") { _ = try NativeAccount.manualGroups("not an address") }
        var settings = NativeSettings()
        settings.inventory = groups; settings.selectedAccountIDs = [groups[0].id]; settings.paused = true
        settings.configuration = try FilteringConfiguration.make(selectedNames: settings.selectedAccountIDs,
            inventory: groups.map { FilteringAccount(id: $0.id, name: $0.id, addresses: $0.addresses) },
            rules: "My custom political policy", evidenceTerms: ["campaign", "Paid for by"], mode: "dry-run")
        try check(settings.configuration!.ownAddresses.contains("other@example.net") && !settings.configuration!.selectedRecipientAddresses.contains("other@example.net"), "unselected addresses remain protected")
        let source = SharedStore(directory: root.appendingPathComponent("source"))
        try source.save(settings)
        _ = try source.protection.reserve(messageID: "source-restored@example.org")
        let original = try Data(contentsOf: source.settingsURL)
        let archive = try source.exportSetup()
        let file = root.appendingPathComponent("setup.json")
        try archive.write(to: file)
        let loaded = try SetupArchive.read(from: file)
        try check(loaded.settings.inventory == settings.inventory && loaded.settings.selectedAccountIDs == settings.selectedAccountIDs, "archive preserves inventory, aliases and selections")
        try check(loaded.settings.paused && loaded.settings.configuration!.mode == "dry-run", "archive preserves pause and preview")
        try check((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private setup export")
        let dest = SharedStore(directory: root.appendingPathComponent("destination"))
        try dest.save(settings)
        _ = try dest.protection.reserve(messageID: "destination-restored@example.org")
        let imported = try dest.importSetup(loaded)
        try check(imported.paused && imported.activationRequired == true, "import preserves pause but requires separate activation")
        try check(imported.revision != settings.revision && imported.inventory == settings.inventory, "import invalidates in-flight results and preserves UI inventory")
        try check(try dest.protects("source-restored@example.org", configuration: imported.configuration!), "source recovery protection committed with settings")
        try check(try dest.protects("destination-restored@example.org", configuration: imported.configuration!), "destination recovery protection preserved")
        try check(try source.settings().revision == settings.revision && Data(contentsOf: source.settingsURL) == original, "export and import do not change source settings")
        let backup = try SetupArchive.read(from: dest.directory.appendingPathComponent("migration-backup.json"))
        try check(backup.settings.revision == settings.revision && backup.protectionDigests.contains(JunkIdentity.key("destination-restored@example.org")), "private destination backup includes recovery state")
        try dest.confirmImportedSetup()
        try check(try dest.settings().paused && dest.settings().activationRequired == false, "confirmation does not override previous pause preference")
        var applyArchive = archive
        applyArchive.settings.paused = false
        let config = settings.configuration!
        applyArchive.settings.configuration = FilteringConfiguration(schemaVersion: 2, mode: "apply", selectedRecipientAddresses: config.selectedRecipientAddresses,
            ownAddresses: config.ownAddresses, rules: config.rules, evidenceTerms: config.evidenceTerms, legacyAccountIDs: config.legacyAccountIDs, protectedCLIIdentities: [])
        let pending = try dest.importSetup(applyArchive)
        try check(try dest.finish(messageID: "eligible@example.org", revision: pending.revision, decision: .political, evidence: "campaign") == .settingsChanged, "apply import cannot move before confirmation")
        try check(try !dest.protection.contains(messageID: "eligible@example.org"), "unconfirmed import does not reserve messages")
        try dest.confirmImportedSetup()
        let active = try dest.settings()
        try check(try dest.finish(messageID: "source-restored@example.org", revision: active.revision, decision: .political, evidence: "campaign") == .protected, "restored message stays protected after activation")
        try check(try dest.finish(messageID: "eligible@example.org", revision: pending.revision, decision: .political, evidence: "campaign") == .settingsChanged, "confirmation rejects stale analysis")
        let beforeFailure = try Data(contentsOf: dest.settingsURL)
        var bad = archive; bad.protectionDigests = ["not a digest"]
        try rejects("invalid protection refuses complete import") { _ = try dest.importSetup(bad) }
        bad = archive; bad.settings.selectedAccountIDs = []
        try rejects("unreconciled UI selection refuses import") { _ = try dest.importSetup(bad) }
        try check(try Data(contentsOf: dest.settingsURL) == beforeFailure, "failed import leaves active settings untouched")
        let folderRead = try SetupArchive.readLegacyFolder(source.directory)
        try check(folderRead.settings.paused && folderRead.protectionDigests == archive.protectionDigests, "explicit legacy folder reads both files")
        try check(try Data(contentsOf: source.settingsURL) == original, "legacy folder read is read-only")
        let empty = root.appendingPathComponent("incomplete")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try original.write(to: empty.appendingPathComponent("settings.json"))
        try rejects("missing legacy protection cannot be silently dropped") { _ = try SetupArchive.readLegacyFolder(empty) }

        let email = root.appendingPathComponent("message.eml")
        let raw = Data("From: Campaign <appeals@example.org>\r\nTo: alias@example.com\r\nMessage-ID: <fixture@example.org>\r\nSubject: =?UTF-8?B?Q2FtcGFpZ24=?=\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nPlease support our campaign".utf8)
        try raw.write(to: email)
        let selection = try MessageDiagnostics.emailFile(email)
        try check(selection.isEmailFile && selection.message.subject == "Campaign", "email-file header decoding")
        try check(selection.selectedAccount(in: settings), "opened file routes using selected alias without inventing a Mail account ID")
        try check(try MIMEBodyDecoder.decode(selection.source).text == "Please support our campaign", "opened file uses production MIME decoder")
        let report = SelectedEmailReport(selection: selection, settings: settings, activity: NativeActivityLog(), analysis: nil, appBuild: "14", extensionBuild: "14")
        try check(report.currentPolicy?.selectedAccount == true, "file report reflects address routing")
        try Data("not an email".utf8).write(to: email)
        try rejects("malformed email file rejected") { _ = try MessageDiagnostics.emailFile(email) }
        try Data(repeating: 65, count: 2 * 1_024 * 1_024 + 1).write(to: email)
        try rejects("oversized email file rejected before decoding") { _ = try MessageDiagnostics.emailFile(email) }

        let logs = SharedStore(directory: root.appendingPathComponent("logs"))
        try logs.record(outcome: "queued", category: "waitingForAnalysis", traceID: "012345abcdef")
        try check(try logs.diagnosticEvents().count == 1, "private file history persists")
        try rejects("diagnostic fields refuse message text") { try logs.record(outcome: "review", category: "PRIVATE email body") }
        try check(try logs.activity().recent.count == 1, "invalid diagnostic event does not modify activity")
        let log = logs.directory.appendingPathComponent("diagnostic.jsonl")
        try check((try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private log permissions")
        for _ in 0..<4 {
            try Data(repeating: 10, count: SharedStore.diagnosticFileLimit - 1).write(to: log)
            try logs.record(outcome: "notPolitical", category: "", processed: true)
        }
        let files = try FileManager.default.contentsOfDirectory(at: logs.directory, includingPropertiesForKeys: [.fileSizeKey]).filter { $0.pathExtension == "jsonl" }
        try check(files.count == 3 && files.allSatisfy { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <= SharedStore.diagnosticFileLimit }, "rotation bounded to three 1 MiB files")
        try check(try logs.diagnosticEvents().last?.outcome == "notPolitical", "rotation keeps latest complete event")
        var old = NativeActivity(outcome: "review", category: "synthetic")
        old.date = Date().addingTimeInterval(-8 * 86400)
        try (JSONEncoder().encode(old) + Data([10])).write(to: log)
        try check(try logs.diagnosticEvents().isEmpty, "seven-day report window excludes old events")
        try FileManager.default.setAttributes([.modificationDate: old.date], ofItemAtPath: log.path)
        try logs.record(outcome: "queued", category: "synthetic")
        try check(try logs.diagnosticEvents().count == 1, "expired file replaced on next write")
        try logs.eraseApplicationData()
        try check(!FileManager.default.fileExists(atPath: log.path), "explicit data erase removes diagnostic files")
        let failure = SharedStore(directory: root.appendingPathComponent("log-failure"))
        try FileManager.default.createDirectory(at: failure.directory.appendingPathComponent("diagnostic.jsonl"), withIntermediateDirectories: true)
        try failure.record(outcome: "review", category: "synthetic")
        try check(try failure.activity().recent.count == 1, "log failure leaves activity usable")
        print("Passed \(count) Store migration, manual setup, email-file and bounded diagnostic checks. Synthetic inputs only; no model or Mail actions.")
    }
}
