import AppKit
import ApplicationServices

enum MailAccessError: LocalizedError {
    case notRunning, denied, unavailable(Int32)
    var errorDescription: String? {
        switch self {
        case .notRunning: return "Open Mail first, or enter addresses and open an email file instead."
        case .denied: return "Mail automation is not authorized. Check System Settings → Privacy & Security → Automation, or use manual addresses and email files."
        case .unavailable(let status): return "Mail automation is unavailable (\(status)). You can use manual addresses and email files."
        }
    }
}

@MainActor
enum MailAccess {
    static func requirePermission() throws {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else { throw MailAccessError.notRunning }
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
        // Called only by explicit Read Accounts / selected-message actions.
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        if status == -1743 || status == -1744 { throw MailAccessError.denied }
        if status != noErr { throw MailAccessError.unavailable(status) }
    }
}

@MainActor
enum AccountInventory {
    static let script = """
    with timeout of 20 seconds
        tell application "/System/Applications/Mail.app"
            set accountNames to get name of every account
            set addressGroups to get email addresses of every account
            set accountIDs to get id of every account
        end tell
        if (count of accountNames) is not (count of addressGroups) or (count of accountNames) is not (count of accountIDs) then error "Mail account inventory mismatch"
        set rows to {}
        repeat with i from 1 to count of accountNames
            set end of rows to {item i of accountIDs, item i of accountNames, item i of addressGroups}
        end repeat
        return rows
    end timeout
    """

    static func read() throws -> [NativeAccount] {
        try MailAccess.requirePermission()
        let rows = try MailAutomation.script(script)
        var accounts: [NativeAccount] = []
        if rows.numberOfItems > 0 {
            for i in 1...rows.numberOfItems {
                guard let row = rows.atIndex(i), row.numberOfItems == 3,
                      let id = row.atIndex(1)?.stringValue, let name = row.atIndex(2)?.stringValue else { throw NativeStoreError.invalidSettings }
                accounts.append(NativeAccount(id: id, name: name, addresses: MailAutomation.addresses(row.atIndex(3))))
            }
        }
        guard !accounts.isEmpty else { throw ToolError("Mail has no configured accounts.") }
        return accounts
    }
}
