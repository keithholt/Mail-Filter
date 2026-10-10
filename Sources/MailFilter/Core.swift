import Foundation

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    var prompt = defaultConfigurationPath("prompts/filter.txt")
    var evidenceTermsFile = defaultConfigurationPath("prompts/political-evidence.txt")
    var limit = 30
    var account: String?
    var accountsFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mail-filter/accounts.txt").path
    var scanAccounts: [String] = []
    var skipProcessed = false
    var showConfig = false
    var fixture: String?
    var junkMailbox = "Junk"
    var apply = false
    var confirm = false
    var check = false
    var checkScripts = false
    var listAccounts = false
    var help = false
    var debugModel = false
    var verbose = false
    var inspectMessage: Int?

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
            case "--evidence-terms": evidenceTermsFile = try value()
            case "--limit":
                guard let n = Int(try value()), (1...50).contains(n) else { throw ToolError("--limit must be 1...50") }
                limit = n
            case "--inspect-message":
                guard let n = Int(try value()), n > 0, n <= Int(Int32.max) else { throw ToolError("--inspect-message requires a positive Mail message ID") }
                inspectMessage = n
            case "--account": account = try value()
            case "--accounts-file": accountsFile = try value()
            case "--skip-processed": skipProcessed = true
            case "--show-config": showConfig = true
            case "--fixture": fixture = try value()
            case "--debug-model": debugModel = true
            case "--verbose", "-v": verbose = true
            case "--junk-mailbox": junkMailbox = try value()
            case "--apply": apply = true
            case "--confirm-junk": confirm = true
            case "--dry-run": break // Explicit read-only override
            case "--check": check = true
            case "--check-scripts": checkScripts = true
            case "--list-accounts": listAccounts = true
            case "--help", "-h": help = true
            default: throw ToolError("Unknown option: \(arg)")
            }
            i += 1
        }
        if arguments.contains("--dry-run") && apply { throw ToolError("--dry-run conflicts with --apply") }
        if confirm && !apply { throw ToolError("--confirm-junk requires --apply") }
        if debugModel && (fixture == nil || apply) {
            throw ToolError("--debug-model requires --fixture and cannot be used with real Mail or --apply")
        }
        if inspectMessage != nil && (account == nil || apply || fixture != nil || debugModel || check || listAccounts) {
            throw ToolError("--inspect-message requires --account and cannot be combined with apply, fixtures, or model diagnostics")
        }
        if apply {
            guard confirm, account != "", !junkMailbox.isEmpty else {
                throw ToolError("Explicit --apply requires --confirm-junk (optional: --account NAME and --junk-mailbox NAME)")
            }
            guard fixture == nil, !check, !checkScripts, !listAccounts, !help, !showConfig else {
                throw ToolError("--apply cannot be combined with fixtures or diagnostic commands")
            }
        }
        let diagnostic = fixture != nil || check || checkScripts || listAccounts || showConfig || help || inspectMessage != nil
        if !apply && !arguments.contains("--dry-run") && !diagnostic {
            apply = true
            confirm = true
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
    var ownAddresses: [String]? = nil

    var hasMeaningfulBody: Bool {
        body.unicodeScalars.contains {
            !$0.properties.isWhitespace && $0.properties.generalCategory != .format &&
            $0.properties.generalCategory != .control && $0.value != 0xFFFC
        }
    }
    var isFromSelf: Bool {
        var address = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = address.lastIndex(of: "<"), let end = address.lastIndex(of: ">"), start < end,
           address[address.index(after: end)...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            address = String(address[address.index(after: start)..<end])
        }
        address = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (ownAddresses ?? []).contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == address }
    }
    var automaticKeepReason: String? {
        if isFromSelf { return "Protected: sender matches one of your addresses across all Mail accounts" }
        if !hasMeaningfulBody { return "Protected: subject-only message or body contains only whitespace/invisible characters" }
        return nil
    }
    var canMove: Bool { !messageID.isEmpty && automaticKeepReason == nil }
    var classificationExcerpt: MailMessage {
        var message = self
        if message.body.count > 6000 {
            message.body = String(message.body.prefix(6000))
            message.truncated = true
        }
        return message
    }

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
    var evidence: String? = nil
    var bodyTruncated: Bool? = nil
}

// Text generation enables Apple's documented source-content transformation mode.
// Unvalidated output must never reach the Mail move operation.
struct Classification: Decodable {
    enum Decision: String, Decodable { case political; case notPolitical = "not-political" }
    let decision: Decision
    let reason: String
    let evidence: String?
}

func parseClassification(_ response: String) throws -> Classification {
    guard response.utf8.count <= 8192 else {
        throw ToolError("Oversized model response; left for review")
    }
    var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
    if json.hasPrefix("```") {
        var lines = json.components(separatedBy: "\n")
        guard lines.count >= 3,
              ["```json", "```"].contains(lines.first!.trimmingCharacters(in: .whitespacesAndNewlines)),
              lines.last!.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
            throw ToolError("Invalid model JSON wrapper; left for review")
        }
        lines.removeFirst()
        lines.removeLast()
        json = lines.joined(separator: "\n")
    }
    // The model can indent JSON with nonbreaking spaces. Normalize whitespace
    // only outside quoted strings; preserve the explanation's text exactly.
    var normalized = ""
    var insideString = false
    var escaped = false
    for scalar in json.unicodeScalars {
        if insideString {
            normalized.unicodeScalars.append(scalar)
            if escaped { escaped = false }
            else if scalar == "\\" { escaped = true }
            else if scalar == "\"" { insideString = false }
        } else {
            if scalar == "\"" { insideString = true }
            if scalar.properties.isWhitespace { normalized.append(" ") }
            else { normalized.unicodeScalars.append(scalar) }
        }
    }
    guard let data = normalized.data(using: .utf8) else {
        throw ToolError("Invalid or oversized model response; left for review")
    }
    do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (Set(object.keys) == Set(["decision", "reason"]) || Set(object.keys) == Set(["decision", "reason", "evidence"])) else {
            throw ToolError("Expected exactly decision and reason fields")
        }
        let value = try JSONDecoder().decode(Classification.self, from: data)
        guard !value.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.reason.count <= 1000 else { throw ToolError("Missing or oversized reason") }
        return value
    } catch {
        throw ToolError("Model returned a refusal or invalid classification JSON; left for review")
    }
}

func parseAccountList(_ text: String) throws -> [String] {
    var names: [String] = []
    for line in text.components(separatedBy: .newlines) {
        let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix("#") { continue }
        if !names.contains(name) { names.append(name) }
    }
    guard !names.isEmpty else { throw ToolError("Account list is empty; enable at least one account in the accounts file") }
    return names
}

func selectedAccountNames(_ options: Options) throws -> [String] {
    if let name = options.account {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError("--account cannot be empty") }
        return [name]
    }
    guard FileManager.default.fileExists(atPath: options.accountsFile) else {
        throw ToolError("Account file missing: \(options.accountsFile). Copy config/accounts.example.txt to ~/.config/mail-filter/accounts.txt and set your exact Mail account names, or use --account NAME. No messages were scanned.")
    }
    return try parseAccountList(String(contentsOfFile: options.accountsFile, encoding: .utf8))
}

enum ReportDestination { case standardOutput, standardError, hidden }

extension Report {
    func destination(verbose: Bool, processingFailed: Bool) -> ReportDestination {
        if processingFailed { return .standardError }
        if verbose || (decision == "political" && ["moved-to-junk", "would-move-to-junk"].contains(action)) {
            return .standardOutput
        }
        return .hidden
    }
}

func politicalEvidenceTerms(_ text: String) throws -> [String] {
    let terms = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    guard !terms.isEmpty else { throw ToolError("Political evidence term list is empty; no messages may be moved") }
    return terms
}

func normalizedEvidence(_ text: String) -> String {
    let cleaned = text.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
    let visible = String(cleaned.unicodeScalars.filter { $0.properties.generalCategory != .format })
    return visible.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

func hasPoliticalTerm(_ text: String, terms: [String]) -> Bool {
    terms.contains { term in
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

@discardableResult
func validatePoliticalEvidence(_ classification: Classification, message: MailMessage, terms: [String]) throws -> String? {
    guard classification.decision == .political else { return nil }
    let evidence = classification.evidence?.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”")) ?? ""
    if !evidence.isEmpty, evidence.count <= 1500, hasPoliticalTerm(evidence, terms: terms) {
        let normalized = normalizedEvidence(evidence)
        if !normalized.isEmpty && (normalizedEvidence(message.subject).contains(normalized) || normalizedEvidence(message.body).contains(normalized)) {
            return evidence
        }
    }
    // A positive model decision with an explicit political subject need not be
    // rejected just because the model omitted or reformatted its quote.
    if !message.subject.isEmpty && hasPoliticalTerm(message.subject, terms: terms) {
        return message.subject
    }
    throw ToolError("Positive classification lacks verifiable political evidence in the message; left for review")
}

func defaultConfigurationPath(_ relative: String) -> String {
    if let root = ProcessInfo.processInfo.environment["MAIL_FILTER_ROOT"], !root.isEmpty {
        return URL(fileURLWithPath: root).appendingPathComponent(relative).path
    }
    // Also support direct invocation of the built executable from any directory.
    var directory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("prompts/filter.txt").path) {
            return directory.appendingPathComponent(relative).path
        }
        directory.deleteLastPathComponent()
    }
    return relative
}
