import Foundation

@main
struct OfflineChecks {
    static var checks = 0
    static func require(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw ToolError(name) }
        checks += 1
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MailFilterStoreFeasibility-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Manually supplied addresses already fit the current routing contract.
        let inventory = [FilteringAccount(id: "manual-1", name: "Filter address", addresses: ["owner@example.com", "alias@example.com"]),
                         FilteringAccount(id: "manual-2", name: "Protected address", addresses: ["other@example.net"])]
        let config = try FilteringConfiguration.make(selectedNames: ["Filter address"], inventory: inventory,
            rules: "Political solicitations only.", evidenceTerms: ["campaign", "Paid for by"], mode: "dry-run")
        try require(config.ownAddresses.count == 3 && config.selectedRecipientAddresses.count == 2, "manual setup preserves separate protected and filtered address sets")
        let mime = Data("From: Example <appeals@example.org>\r\nTo: owner@example.com\r\nMessage-ID: <fixture@example.org>\r\nSubject: An appeal\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nPlease support our campaign. Paid for by Example Committee.".utf8)
        let decoded = try MIMEBodyDecoder.decode(mime)
        try require(decoded.text.contains("Paid for by Example Committee"), "user-opened email source can reuse the existing MIME decoder")
        guard case .classify(let candidate) = config.input(messageID: "fixture@example.org", sender: "appeals@example.org",
            subject: "An appeal", recipients: ["owner@example.com"], body: decoded) else { throw ToolError("manual address routing rejected external fixture") }
        try require(candidate.canMove, "manual address configuration reaches the existing classifier guards")
        guard case .skip(.selfMail) = config.input(messageID: "self@example.org", sender: "other@example.net", subject: "Forwarded appeal",
            recipients: ["alias@example.com"], body: decoded) else { throw ToolError("manual setup lost cross-account self protection") }
        checks += 1

        let source = SharedStore(directory: root.appendingPathComponent("source"))
        var settings = NativeSettings()
        settings.configuration = config
        settings.inventory = inventory.map { NativeAccount(id: $0.id, name: $0.name, addresses: $0.addresses) }
        settings.selectedAccountIDs = ["manual-1"]
        settings.paused = true
        try source.save(settings)
        _ = try source.protection.reserve(messageID: "restored@example.org")
        let destination = SharedStore(directory: root.appendingPathComponent("destination"))
        _ = try destination.importSetup(source.exportSetup())
        try require(try destination.settings().configuration?.rules == config.rules, "explicit migration preserves policy")
        try require(try destination.protects("restored@example.org", configuration: config), "explicit migration preserves restored-message identity")
        try require(try destination.settings().paused && destination.settings().selectedAccountIDs == ["manual-1"]
                    && destination.settings().activationRequired == true,
                    "complete migration preserves pause and UI selection while waiting for confirmation")
        try require(try source.settings().paused, "migration leaves source settings unchanged")
        try destination.record(outcome: "review", category: "syntheticExport", traceID: "012345abcdef")
        let activity = try String(contentsOf: destination.activityURL, encoding: .utf8)
        try require(!activity.contains("owner@example.com") && !activity.contains("Paid for by"), "support activity excludes addresses and source evidence")
        try require(try FileManager.default.attributesOfItem(atPath: destination.activityURL.path)[.posixPermissions] as? NSNumber == 0o600,
                    "support activity has owner-only permissions")
        print("Passed \(checks) offline App Store routing, email-file, migration and private activity checks. No model calls or Mail access.")
    }
}
