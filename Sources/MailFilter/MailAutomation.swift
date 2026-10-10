import AppKit

@MainActor
struct MailAutomation {
    static func script(_ source: String, execute: Bool = true) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw ToolError("Cannot create AppleScript") }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { throw ToolError("AppleScript compile error: \(error ?? [:])") }
        if !execute { return NSAppleEventDescriptor() }
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            let hint = number == -1712
                ? "Mail did not respond within 20 seconds. Open Mail, select the account Inbox, allow it to finish syncing, and retry with --limit 1."
                : number == -1743
                ? "Allow your terminal to control Mail in System Settings > Privacy & Security > Automation."
                : "Open Mail and retry from a normal Terminal session; this environment may restrict Apple events or application launching."
            throw ToolError("Mail automation failed: \(error). \(hint)")
        }
        return result
    }

    static let accountsScript = """
    tell application "/System/Applications/Mail.app"
        set rows to {}
        repeat with a in accounts
            set end of rows to {id of a, name of a}
        end repeat
        return rows
    end tell
    """

    static let ownAddressCollection = """
    set protectedAddresses to {}
    set addressGroups to get email addresses of every account
    repeat with addressGroup in addressGroups
        set protectedAddresses to protectedAddresses & (contents of addressGroup)
    end repeat
    """

    static func readScript(_ options: Options) -> String {
        // Validate every requested account before reading any messages. Never
        // fall back to scanning all accounts when a name or config is invalid.
        let names = options.scanAccounts.isEmpty ? (options.account.map { [$0] } ?? []) : options.scanAccounts
        let literals = names.map(appleString).joined(separator: ", ")
        let select = """
        set selectedAccounts to {}
        set requestedNames to {\(literals)}
        if (count of requestedNames) is 0 then error "No scan accounts selected"
        repeat with requestedName in requestedNames
            set matchedAccounts to accounts whose name is (contents of requestedName)
            if (count of matchedAccounts) is not 1 then error "Configured account must match exactly one Mail account: " & (contents of requestedName)
            set end of selectedAccounts to item 1 of matchedAccounts
        end repeat
        """
        return """
        on cleanText(v)
            if v is missing value then return ""
            return v as text
        end cleanText
        with timeout of 20 seconds
            tell application "/System/Applications/Mail.app"
                \(ownAddressCollection)
                set rows to {}
                set inspected to 0
                \(select)
                repeat with a in selectedAccounts
                    if inspected ≥ \(options.limit) then exit repeat
                    set inboxes to mailboxes of a whose name is "INBOX"
                    if (count of inboxes) is not 1 then error "Account Inbox not found uniquely (expected INBOX); no mail changed"
                    set box to item 1 of inboxes
                    set n to count of messages of box
                    set remaining to \(options.limit) - inspected
                    if n > remaining then set n to remaining
                    repeat with i from 1 to n
                        set inspected to inspected + 1
                        set m to message i of box
                        if deleted status of m is false then
                            set b to my cleanText(content of m)
                            set cut to false
                            if (length of b) > 6000 then
                                set b to text 1 thru 6000 of b
                                set cut to true
                            end if
                            set end of rows to {id of a, name of a, id of m, my cleanText(message id of m), my cleanText(subject of m), my cleanText(sender of m), b, cut, protectedAddresses}
                        end if
                    end repeat
                end repeat
                return rows
            end tell
        end timeout
        """
    }

    static func addresses(_ descriptor: NSAppleEventDescriptor?) -> [String] {
        guard let descriptor, descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0)?.stringValue }
    }

    static func inspectScript(account: String, id: Int) -> String {
        """
        on cleanText(v)
            if v is missing value then return ""
            return v as text
        end cleanText
        with timeout of 20 seconds
            tell application "/System/Applications/Mail.app"
                \(ownAddressCollection)
                set selectedAccounts to accounts whose name is \(appleString(account))
                if (count of selectedAccounts) is not 1 then error "Account name must match exactly one account"
                set a to item 1 of selectedAccounts
                set inboxes to mailboxes of a whose name is "INBOX"
                if (count of inboxes) is not 1 then error "Account Inbox not found uniquely"
                set box to item 1 of inboxes
                set found to messages of box whose id is \(id)
                if (count of found) is not 1 then error "Message ID not found uniquely in this account Inbox"
                set m to item 1 of found
                set b to my cleanText(content of m)
                set originalLength to length of b
                if originalLength > 6000 then set b to text 1 thru 6000 of b
                return {id of a, name of a, id of m, my cleanText(message id of m), my cleanText(subject of m), my cleanText(sender of m), b, originalLength > 6000, protectedAddresses, originalLength}
            end tell
        end timeout
        """
    }

    static func readMessage(account: String, id: Int) throws -> MailMessage {
        let row = try script(inspectScript(account: account, id: id))
        guard row.numberOfItems == 10 else { throw ToolError("Unexpected single-message response") }
        return MailMessage(accountID: row.atIndex(1)?.stringValue ?? "", account: account, id: id,
            messageID: row.atIndex(4)?.stringValue ?? "", subject: row.atIndex(5)?.stringValue ?? "",
            sender: row.atIndex(6)?.stringValue ?? "", body: row.atIndex(7)?.stringValue ?? "",
            truncated: row.atIndex(8)?.booleanValue ?? false, ownAddresses: addresses(row.atIndex(9)))
    }

    static func inspect(account: String, id: Int) throws {
        let row = try script(inspectScript(account: account, id: id))
        guard row.numberOfItems == 10 else { throw ToolError("Unexpected inspection response") }
        let message = MailMessage(accountID: row.atIndex(1)!.stringValue ?? "", account: account, id: id,
            messageID: row.atIndex(4)!.stringValue ?? "", subject: row.atIndex(5)!.stringValue ?? "",
            sender: row.atIndex(6)!.stringValue ?? "", body: row.atIndex(7)!.stringValue ?? "",
            truncated: row.atIndex(8)!.booleanValue, ownAddresses: addresses(row.atIndex(9)))
        let output: [String: Any] = [
            "account": account, "id": id, "subject": message.subject, "sender": message.sender,
            "mailBodyLength": Int(row.atIndex(10)!.int32Value), "hasMeaningfulBody": message.hasMeaningfulBody,
            "isFromSelf": message.isFromSelf, "automaticKeepReason": message.automaticKeepReason ?? "none",
            "bodyPreview": String(message.body.prefix(2000)), "previewTruncated": message.body.count > 2000 || message.truncated,
            "bodyScalarPreview": message.body.unicodeScalars.prefix(80).map { String(format: "U+%04X", $0.value) }
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func read(_ options: Options) throws -> [MailMessage] {
        let rows = try script(readScript(options))
        return try (1...max(rows.numberOfItems, 1)).compactMap { i in
            if rows.numberOfItems == 0 { return nil }
            guard let row = rows.atIndex(i), row.numberOfItems == 9 else { throw ToolError("Unexpected Mail response") }
            func text(_ index: Int) throws -> String {
                guard let value = row.atIndex(index)?.stringValue else { throw ToolError("Missing Mail field \(index)") }
                return value
            }
            return try MailMessage(accountID: text(1), account: text(2), id: Int(row.atIndex(3)!.int32Value), messageID: text(4), subject: text(5), sender: text(6), body: text(7), truncated: row.atIndex(8)!.booleanValue, ownAddresses: addresses(row.atIndex(9)))
        }
    }

    static func moveScript(_ message: MailMessage, to destination: String) -> String {
        let excerptCheck = message.truncated ? """
        if (length of currentBody) ≤ 6000 then error "Message excerpt status changed"
        set currentBody to text 1 thru 6000 of currentBody
        """ : ""
        return """
        tell application "/System/Applications/Mail.app"
            set a to first account whose id is \(appleString(message.accountID))
            set targets to mailboxes of a whose name is \(appleString(destination))
            if (count of targets) is not 1 then error "Destination mailbox must exist uniquely at the account root"
            set targetBox to item 1 of targets
            set candidates to messages of inbox whose id is \(message.id)
            set matches to {}
            repeat with m in candidates
                if id of account of mailbox of m is \(appleString(message.accountID)) then set end of matches to contents of m
            end repeat
            if (count of matches) is not 1 then error "Message no longer uniquely present in Inbox"
            set m to item 1 of matches
            if message id of m is not \(appleString(message.messageID)) then error "Message identity changed"
            if subject of m is not \(appleString(message.subject)) then error "Message subject changed"
            if sender of m is not \(appleString(message.sender)) then error "Message sender changed"
            set currentBody to content of m
            if currentBody is missing value then error "Message body unavailable"
            \(excerptCheck)
            if currentBody is not \(appleString(message.body)) then error "Message body or classified excerpt changed"
            if deleted status of m then error "Message already deleted"
            move m to targetBox
            return "moved"
        end tell
        """
    }

    static func move(_ message: MailMessage, options: Options) throws {
        guard options.apply, options.confirm, options.fixture == nil,
              (options.scanAccounts.contains(message.account) || options.account == message.account), message.canMove,
              !options.junkMailbox.isEmpty else { throw ToolError("Safety checks prevented moving this message") }
        _ = try script(moveScript(message, to: options.junkMailbox))
    }
}
