import AppKit

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
