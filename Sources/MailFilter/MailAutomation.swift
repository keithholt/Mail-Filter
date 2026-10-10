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
            let hint = number == -1743
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

    static func readScript(_ options: Options) -> String {
        let filter = options.account.map { "if name of a is not \(appleString($0)) then error \"Skip other account\"" } ?? ""
        return """
        on cleanText(v)
            if v is missing value then return ""
            return v as text
        end cleanText
        tell application "/System/Applications/Mail.app"
            set rows to {}
            set candidates to messages of inbox
            repeat with m in candidates
                if (count of rows) ≥ \(options.limit) then exit repeat
                set a to account of mailbox of m
                try
                    \(filter)
                    if deleted status of m is false then
                        set b to my cleanText(content of m)
                        set cut to false
                        if (length of b) > 6000 then
                            set b to text 1 thru 6000 of b
                            set cut to true
                        end if
                        set end of rows to {id of a, name of a, id of m, my cleanText(message id of m), my cleanText(subject of m), my cleanText(sender of m), b, cut}
                    end if
                on error errText number errNum
                    if errText is not "Skip other account" then error errText number errNum
                end try
            end repeat
            return rows
        end tell
        """
    }

    static func read(_ options: Options) throws -> [MailMessage] {
        let rows = try script(readScript(options))
        return try (1...max(rows.numberOfItems, 1)).compactMap { i in
            if rows.numberOfItems == 0 { return nil }
            guard let row = rows.atIndex(i), row.numberOfItems == 8 else { throw ToolError("Unexpected Mail response") }
            func text(_ index: Int) throws -> String {
                guard let value = row.atIndex(index)?.stringValue else { throw ToolError("Missing Mail field \(index)") }
                return value
            }
            return try MailMessage(accountID: text(1), account: text(2), id: Int(row.atIndex(3)!.int32Value), messageID: text(4), subject: text(5), sender: text(6), body: text(7), truncated: row.atIndex(8)!.booleanValue)
        }
    }

    static func moveScript(_ message: MailMessage, to destination: String) -> String {
        """
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
            if content of m is not \(appleString(message.body)) then error "Message body changed"
            if deleted status of m then error "Message already deleted"
            move m to targetBox
            return "moved"
        end tell
        """
    }

    static func move(_ message: MailMessage, options: Options) throws {
        guard options.apply, options.confirm, options.fixture == nil,
              options.account == message.account, message.canMove,
              let destination = options.trashMailbox else { throw ToolError("Safety checks prevented moving this message") }
        _ = try script(moveScript(message, to: destination))
    }
}
