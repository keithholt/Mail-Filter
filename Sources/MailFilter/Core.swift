import Foundation

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    var prompt = "prompts/filter.txt"
    var limit = 10
    var account: String?
    var fixture: String?
    var trashMailbox: String?
    var apply = false
    var confirm = false
    var check = false
    var checkScripts = false
    var listAccounts = false
    var help = false

    init(_ arguments: [String]) throws {
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            func value() throws -> String {
                guard i + 1 < arguments.count else { throw ToolError("Missing value for \(arg)") }
                i += 1
                return arguments[i]
            }
            switch arg {
            case "--prompt": prompt = try value()
            case "--limit":
                guard let n = Int(try value()), (1...100).contains(n) else { throw ToolError("--limit must be 1...100") }
                limit = n
            case "--account": account = try value()
            case "--fixture": fixture = try value()
            case "--trash-mailbox": trashMailbox = try value()
            case "--apply": apply = true
            case "--confirm-trash": confirm = true
            case "--dry-run": break // default; conflicting flags rejected below
            case "--check": check = true
            case "--check-scripts": checkScripts = true
            case "--list-accounts": listAccounts = true
            case "--help", "-h": help = true
            default: throw ToolError("Unknown option: \(arg)")
            }
            i += 1
        }
        if arguments.contains("--dry-run") && apply { throw ToolError("--dry-run conflicts with --apply") }
        if confirm && !apply { throw ToolError("--confirm-trash requires --apply") }
        if apply {
            guard confirm, let account, !account.isEmpty, let trashMailbox, !trashMailbox.isEmpty else {
                throw ToolError("Moving mail requires --apply --confirm-trash --account NAME --trash-mailbox NAME")
            }
            guard fixture == nil, !check, !checkScripts, !listAccounts, !help else {
                throw ToolError("--apply cannot be combined with fixtures or diagnostic commands")
            }
        }
    }
}

struct MailMessage: Codable, Equatable {
    var accountID: String
    var account: String
    var id: Int
    var messageID: String
    var subject: String
    var sender: String
    var body: String
    var truncated: Bool

    var canMove: Bool { !truncated && !messageID.isEmpty && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// Escape AppleScript literals, never shell-interpolate email or account data.
func appleString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

struct Report: Codable {
    let account: String
    let id: Int
    let subject: String
    let decision: String
    let reason: String
    let action: String
}
