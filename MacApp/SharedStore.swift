import Foundation
import Darwin
import CryptoKit

enum NativeStoreError: LocalizedError {
    case unavailable, invalidSettings, busy, invalidActivity
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Private settings couldn't be opened. Allow Mail-Filter access if macOS asks, then reopen the app."
        case .invalidSettings: return "The saved settings are damaged or unsupported. Filtering has stopped; restore a valid settings backup."
        case .busy: return "Another operation is updating the settings. Try again shortly."
        case .invalidActivity: return "Recent activity could not be read. Restored-message protection is separate."
        }
    }
}

struct NativeAccount: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let addresses: [String]

    /// Mail's successful inventory replaces the displayed list, including manual
    /// groups from an earlier refresh. Never resurrect removed addresses as accounts.
    static func refreshed(_ discovered: [NativeAccount], replacing previous: [NativeAccount], selectedIDs: Set<String>,
                          fallbackSelectedAddresses: [String] = []) -> (accounts: [NativeAccount], selection: Set<String>) {
        let previousIDs = Set(previous.map(\.id))
        let selectedAddresses = Set((previous.isEmpty ? fallbackSelectedAddresses
            : previous.filter { selectedIDs.contains($0.id) }.flatMap(\.addresses)).map(normalizedEmailAddress))
        let selection = Set(discovered.filter { account in
            // Stable Mail IDs retain checked AND unchecked choices even when
            // aliases change. Address matching supports a prior manual setup.
            previousIDs.contains(account.id) ? selectedIDs.contains(account.id)
                : !selectedAddresses.isDisjoint(with: account.addresses.map(normalizedEmailAddress))
        }.map(\.id))
        return (discovered, selection)
    }

    /// Each line is one local address group, with aliases separated by commas.
    /// IDs remain local; they are never presented as Mail account identifiers.
    static func manualGroups(_ text: String) throws -> [NativeAccount] {
        var seen = Set<String>()
        let groups = try text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { line in
            let addresses = line.split(separator: ",", omittingEmptySubsequences: false).map { normalizedEmailAddress(String($0)) }
            guard !addresses.isEmpty, addresses.allSatisfy({ address in
                address.range(of: "^[^@\\s,<>]+@[^@\\s,<>]+\\.[^@\\s,<>]+$", options: .regularExpression) != nil
                && address.count <= 320 && seen.insert(address).inserted
            }) else { throw NativeStoreError.invalidSettings }
            return NativeAccount(id: "manual-" + (try JunkIdentity.hash(addresses.sorted())), name: addresses[0], addresses: addresses)
        }
        guard !groups.isEmpty, groups.count <= 1_024, seen.count <= 1_024 else { throw NativeStoreError.invalidSettings }
        return groups
    }
}

struct NativeSettings: Codable {
    var schemaVersion = 1
    var revision = UUID().uuidString
    var paused = false
    var inventory: [NativeAccount] = []
    var selectedAccountIDs: [String] = []
    var configuration: FilteringConfiguration?
    // Optional additions preserve schema-1 installations. Migration protection
    // commits atomically with imported settings and is independent of log expiry.
    var importedProtection: [String]? = nil
    var activationRequired: Bool? = nil
    #if MAIL_FILTER_DEV
    // Dev-only, opt-in and backward compatible with existing private settings.
    var filterOwnMailForTesting: Bool? = nil
    #endif

    var allowsOwnMailForTesting: Bool {
        #if MAIL_FILTER_DEV
        return filterOwnMailForTesting == true
        #else
        return false
        #endif
    }

    func validate() throws {
        guard schemaVersion == 1, UUID(uuidString: revision) != nil,
              inventory.count <= 1_024, selectedAccountIDs.count <= 1_024,
              Set(inventory.map(\.id)).count == inventory.count,
              inventory.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 256 && !$0.name.isEmpty && $0.name.count <= 500 && $0.addresses.count <= 1_024 }),
              inventory.flatMap(\.addresses).allSatisfy({ $0.count <= 320 }),
              Set(selectedAccountIDs).isSubset(of: Set(inventory.map(\.id))) else { throw NativeStoreError.invalidSettings }
        guard (importedProtection?.count ?? 0) <= 100_000,
              importedProtection?.allSatisfy(JunkIdentity.isDigest) != false else { throw NativeStoreError.invalidSettings }
        try configuration?.validate()
    }
}

struct SetupArchive: Codable {
    var schemaVersion = 1
    var exportedAt = Date()
    var settings: NativeSettings
    var protectionDigests: [String]

    func validate() throws {
        try settings.validate()
        guard schemaVersion == 1, protectionDigests.count <= 100_000,
              protectionDigests.allSatisfy(JunkIdentity.isDigest) else { throw NativeStoreError.invalidSettings }
        guard let configuration = settings.configuration else {
            guard settings.inventory.isEmpty, settings.selectedAccountIDs.isEmpty else { throw NativeStoreError.invalidSettings }
            return
        }
        guard !settings.selectedAccountIDs.isEmpty else { throw NativeStoreError.invalidSettings }
        let inventory = settings.inventory.map { FilteringAccount(id: $0.id, name: $0.id, addresses: $0.addresses) }
        let rebuilt = try FilteringConfiguration.make(selectedNames: settings.selectedAccountIDs, inventory: inventory,
            rules: configuration.rules, evidenceTerms: configuration.evidenceTerms, mode: configuration.mode)
        guard Set(rebuilt.ownAddresses) == Set(configuration.ownAddresses.map(normalizedEmailAddress)),
              Set(rebuilt.selectedRecipientAddresses) == Set(configuration.selectedRecipientAddresses.map(normalizedEmailAddress)) else {
            throw NativeStoreError.invalidSettings
        }
    }

    static func read(from url: URL) throws -> SetupArchive {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
        let data = try Data(contentsOf: url)
        guard data.count <= 20 * 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
        let result = try JSONDecoder().decode(Self.self, from: data)
        try result.validate()
        return result
    }

    static func readLegacyFolder(_ directory: URL) throws -> SetupArchive {
        let url = directory.appendingPathComponent("settings.json")
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 16 * 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
        let data = try Data(contentsOf: url)
        guard data.count <= 16 * 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
        let settings = try JSONDecoder().decode(NativeSettings.self, from: data)
        let digests = try JunkProtection.readDigests(directory.appendingPathComponent("junk-protection.json"))
        let archive = SetupArchive(settings: settings, protectionDigests: Array(digests).sorted())
        try archive.validate()
        return archive
    }

    func write(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct NativeActivity: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    let outcome: String
    let category: String
    var traceID: String? = nil
    var attempt: Int? = nil
    var failureDomain: String? = nil
    var failureCode: Int? = nil
    var modelMetrics: ModelRequestMetrics? = nil
    var bodyWaitMilliseconds: Int? = nil
    var build: String? = nil
    var channel: String? = nil
    var queueWaitMilliseconds: Int? = nil
    var modelSlotBusy: Bool? = nil
    var modelSlotWaiters: Int? = nil

    var measurementSummary: String {
        var values: [String] = []
        if let modelMetrics { values.append(modelMetrics.summary) }
        if let bodyWaitMilliseconds { values.append("bodyWaitMs=\(bodyWaitMilliseconds)") }
        if let queueWaitMilliseconds { values.append("queueWaitMs=\(queueWaitMilliseconds)") }
        if let modelSlotBusy { values.append("modelSlotBusy=\(modelSlotBusy)") }
        if let modelSlotWaiters { values.append("modelSlotWaiters=\(modelSlotWaiters)") }
        return values.joined(separator: " ")
    }
}

/// Private rejected output only. Kept out of ordinary activity, Console and
/// application support reports; included only in an explicit same-email export.
struct ModelFailureRecord: Codable, Sendable {
    var date = Date()
    let traceID: String
    let attempt: Int
    let policyRevision: String
    let build: String?
    let metrics: ModelRequestMetrics
    let replyUTF8Base64: String
    let replyTruncated: Bool
    let replySHA256: String

    var valid: Bool {
        guard traceID.count == 12, traceID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (1...10).contains(attempt), policyRevision.count <= 100,
              build == nil || (build!.count <= 50 && build!.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil),
              metrics.valid, [.emptyResponse, .blankResponse, .invalidLabel, .refusal].contains(metrics.status),
              replyUTF8Base64.utf8.count <= 10_924, let bytes = Data(base64Encoded: replyUTF8Base64), bytes.count <= 8192,
              replySHA256.count == 64, replySHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return false }
        return replyTruncated || SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == replySHA256
    }
}

struct NativeActivityLog: Codable {
    static let maximumRecent = 500
    static let maximumBytes = 1_024 * 1_024
    var schemaVersion = 1
    var processed = 0
    var junkRequested = 0
    var recent: [NativeActivity] = []
    // Optional fields keep existing version-5 activity files compatible.
    var receivedCallbacks: Int? = nil
    var lastCallback: Date? = nil
    // Retain startup identity even after it leaves the bounded recent-event list.
    // A recorded start is historical evidence, not a process liveness check.
    var lastExtensionStart: NativeActivity? = nil
}

enum NativeOutcome: String {
    case junkRequested, previewPolitical, notPolitical, protected, settingsChanged
}

enum NativeStorage {
    static let localRelativePath = "Library/Application Support/Mail-Filter Local"

    static func directory(mode: String, group: String?, userHome: URL,
                          groupContainer: (String) -> URL?) throws -> URL {
        switch mode {
        case "local-development":
            return userHome.appendingPathComponent(localRelativePath, isDirectory: true)
        case "app-group":
            guard let group, !group.isEmpty, let root = groupContainer(group) else { throw NativeStoreError.unavailable }
            return root.appendingPathComponent("Mail-Filter", isDirectory: true)
        default:
            throw NativeStoreError.unavailable
        }
    }

    // FileManager's home directory is the extension's sandbox home. Resolve the
    // account home instead, matching the local build's home-relative entitlement.
    static func accountHome() throws -> URL {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        let home: String? = buffer.withUnsafeMutableBufferPointer { storage in
            guard getpwuid_r(getuid(), &entry, storage.baseAddress, storage.count, &result) == 0,
                  result != nil, let path = entry.pw_dir else { return nil }
            return String(cString: path)
        }
        guard let home, home.hasPrefix("/"), home != "/" else { throw NativeStoreError.unavailable }
        return URL(fileURLWithPath: home, isDirectory: true)
    }
}

/// No dependency on the settings app remaining open. Both processes resolve the
/// same private store, and recheck settings under a lock before any action.
final class SharedStore {
    let directory: URL
    var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    var activityURL: URL { directory.appendingPathComponent("activity.json") }
    var modelFailuresURL: URL { directory.appendingPathComponent("model-failures.json") }
    var protection: JunkProtection { JunkProtection(url: directory.appendingPathComponent("junk-protection.json")) }

    init(directory: URL) { self.directory = directory }

    static func production(bundle: Bundle = .main) throws -> SharedStore {
        let mode = bundle.object(forInfoDictionaryKey: "MailFilterStorageMode") as? String ?? "app-group"
        let group = bundle.object(forInfoDictionaryKey: "MailFilterAppGroup") as? String
        let home = mode == "local-development" ? try NativeStorage.accountHome() : FileManager.default.homeDirectoryForCurrentUser
        let directory = try NativeStorage.directory(mode: mode, group: group, userHome: home) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
        return SharedStore(directory: directory)
    }

    func settings() throws -> NativeSettings { try locked { try loadSettings() } }

    /// Upgrade only the untouched shipped word list. Preserve custom vocabulary,
    /// account selections, rules, mode, pause state, activity and protection.
    func updateStandardVerificationWords() throws -> Bool {
        try locked {
            var settings = try loadSettings()
            guard let original = settings.configuration else { return false }
            let saved = Set(original.evidenceTerms.map { $0.lowercased() })
            let previous = Set(PoliticalVerificationWords.previousDefaults.map { $0.lowercased() })
            let version9 = Set((PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.firstAdditions).map { $0.lowercased() })
            let version11 = Set((PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.version11Additions).map { $0.lowercased() })
            let version12 = Set((PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.version12Additions).map { $0.lowercased() })
            guard saved == previous || saved == version9 || saved == version11 || saved == version12 else { return false }
            let additions = PoliticalVerificationWords.additions.filter { !saved.contains($0.lowercased()) }
            settings.configuration = FilteringConfiguration(schemaVersion: original.schemaVersion, mode: original.mode,
                selectedRecipientAddresses: original.selectedRecipientAddresses, ownAddresses: original.ownAddresses,
                rules: original.rules, evidenceTerms: original.evidenceTerms + additions,
                legacyAccountIDs: original.legacyAccountIDs, protectedCLIIdentities: original.protectedCLIIdentities)
            settings.revision = UUID().uuidString
            try settings.validate()
            try write(settings, to: settingsURL)
            return true
        }
    }

    /// Refresh only the prior untouched standard prompt. Edited policies survive
    /// upgrades, as do all accounts, pause/preview and restored-mail protection.
    func updateStandardPrompt(_ rules: String, replacingDigest: String? = nil) throws -> Bool {
        try locked {
            var settings = try loadSettings()
            guard let original = settings.configuration else { return false }
            let digest = SHA256.hash(data: Data(original.rules.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map { String(format: "%02x", $0) }.joined()
            let recognized = replacingDigest.map { [$0] } ?? [
                "818fba6fb1f6c4fc2ae6869b24ba55e50bf356ee28d86eb07c161ce912264968",
                "4f12418bfe71184f37662f5a1b06a8d6ac2aa13c643c51dd4989cb5baccbe26f"
            ]
            guard recognized.contains(digest), original.rules != rules else { return false }
            settings.configuration = FilteringConfiguration(schemaVersion: original.schemaVersion, mode: original.mode,
                selectedRecipientAddresses: original.selectedRecipientAddresses, ownAddresses: original.ownAddresses,
                rules: rules, evidenceTerms: original.evidenceTerms, legacyAccountIDs: original.legacyAccountIDs,
                protectedCLIIdentities: original.protectedCLIIdentities)
            settings.revision = UUID().uuidString
            try settings.validate()
            try write(settings, to: settingsURL)
            return true
        }
    }

    func save(_ settings: NativeSettings) throws {
        try settings.validate()
        try locked { try write(settings, to: settingsURL) }
    }

    func setPaused(_ paused: Bool) throws {
        try locked {
            var settings = try loadSettings()
            settings.paused = paused
            settings.revision = UUID().uuidString
            try write(settings, to: settingsURL)
        }
    }

    func confirmImportedSetup() throws {
        try locked {
            var settings = try loadSettings()
            guard settings.configuration != nil else { throw NativeStoreError.invalidSettings }
            settings.activationRequired = false
            settings.revision = UUID().uuidString
            try write(settings, to: settingsURL)
        }
    }

    func exportSetup() throws -> SetupArchive {
        try locked { try snapshot() }
    }

    private func snapshot() throws -> SetupArchive {
        let settings = try loadSettings()
        let saved = FileManager.default.fileExists(atPath: directory.appendingPathComponent("junk-protection.json").path)
            ? try JunkProtection.readDigests(directory.appendingPathComponent("junk-protection.json")) : []
        return SetupArchive(settings: settings, protectionDigests: Array(saved.union(settings.importedProtection ?? [])).sorted())
    }

    /// One atomic settings replacement includes incoming protection. A failed
    /// import can add no action permission. A private backup supports rollback.
    func importSetup(_ archive: SetupArchive) throws -> NativeSettings {
        try archive.validate()
        return try locked {
            let previous = try snapshot()
            var imported = archive.settings
            let protection = Set(previous.protectionDigests + archive.protectionDigests + (imported.importedProtection ?? []))
            guard protection.count <= 100_000 else { throw NativeStoreError.invalidSettings }
            if let old = previous.settings.configuration, let incoming = imported.configuration {
                imported.configuration = FilteringConfiguration(schemaVersion: 2, mode: incoming.mode,
                    selectedRecipientAddresses: incoming.selectedRecipientAddresses, ownAddresses: incoming.ownAddresses,
                    rules: incoming.rules, evidenceTerms: incoming.evidenceTerms,
                    legacyAccountIDs: Array(Set(old.legacyAccountIDs + incoming.legacyAccountIDs)).sorted(),
                    protectedCLIIdentities: Array(Set(old.protectedCLIIdentities + incoming.protectedCLIIdentities)).sorted())
            }
            imported.importedProtection = protection.sorted()
            imported.activationRequired = imported.configuration != nil
            imported.revision = UUID().uuidString
            try imported.validate()
            // Backup is not an import source until the user explicitly selects it.
            try write(previous, to: directory.appendingPathComponent("migration-backup.json"))
            try write(imported, to: settingsURL)
            return imported
        }
    }

    func protects(_ messageID: String, configuration: FilteringConfiguration) throws -> Bool {
        try locked {
            let settings = try loadSettings()
            return try (settings.importedProtection ?? []).contains(JunkIdentity.key(messageID))
                || JunkIdentity.protectedByCLI(messageID: messageID, accountIDs: configuration.legacyAccountIDs,
                                          identities: configuration.protectedCLIIdentities) || protection.contains(messageID: messageID)
        }
    }

    func finish(messageID: String, revision: String, decision: Classification.Decision, evidence: String?) throws -> NativeOutcome {
        try locked {
            let current = try loadSettings()
            guard !current.paused, current.activationRequired != true, current.revision == revision, let configuration = current.configuration else { return .settingsChanged }
            guard decision == .political else { return .notPolitical }
            guard configuration.evidenceTerms.isEmpty || evidence?.isEmpty == false else { return .notPolitical }
            if try (current.importedProtection ?? []).contains(JunkIdentity.key(messageID)) || JunkIdentity.protectedByCLI(messageID: messageID, accountIDs: configuration.legacyAccountIDs,
                                              identities: configuration.protectedCLIIdentities) || protection.contains(messageID: messageID) { return .protected }
            if configuration.mode == "dry-run" { return .previewPolitical }
            return try protection.reserve(messageID: messageID) ? .junkRequested : .protected
        }
    }

    func importProtection(from source: URL) throws { try locked { try protection.importProtection(from: source) } }

    func importSetup(configuration: FilteringConfiguration, protectionFile: URL?) throws -> NativeSettings {
        try configuration.validate()
        // Validate the source first; a broken migration cannot replace settings.
        if let protectionFile { _ = try JunkProtection.readDigests(protectionFile) }
        return try locked {
            let current = try loadSettings()
            let merged = FilteringConfiguration(schemaVersion: 2, mode: configuration.mode,
                selectedRecipientAddresses: configuration.selectedRecipientAddresses, ownAddresses: configuration.ownAddresses,
                rules: configuration.rules, evidenceTerms: configuration.evidenceTerms,
                legacyAccountIDs: Array(Set(configuration.legacyAccountIDs + (current.configuration?.legacyAccountIDs ?? []))).sorted(),
                protectedCLIIdentities: Array(Set(configuration.protectedCLIIdentities + (current.configuration?.protectedCLIIdentities ?? []))).sorted())
            try merged.validate()
            if let protectionFile { try protection.importProtection(from: protectionFile) }
            var settings = current
            settings.configuration = merged
            settings.inventory = []; settings.selectedAccountIDs = []
            settings.revision = UUID().uuidString
            try write(settings, to: settingsURL)
            return settings
        }
    }

    func activity() throws -> NativeActivityLog { try locked { try loadActivity() } }

    static func validEvent(_ event: NativeActivity) -> Bool {
        func token(_ value: String, limit: Int, empty: Bool = false) -> Bool {
            (empty && value.isEmpty) || (value.count <= limit && value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil)
        }
        return token(event.outcome, limit: 80) && token(event.category, limit: 100, empty: true)
            && (event.traceID == nil || (event.traceID!.count == 12 && event.traceID!.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }))
            && (event.attempt == nil || (1...10).contains(event.attempt!))
            && ((event.failureDomain == nil) == (event.failureCode == nil))
            && (event.failureDomain == nil || token(event.failureDomain!, limit: 200))
            && (event.build == nil || token(event.build!, limit: 50))
            && (event.channel == nil || token(event.channel!, limit: 50))
            && (event.modelMetrics == nil || event.modelMetrics!.valid)
            && (event.bodyWaitMilliseconds == nil || (0...1_000_000_000).contains(event.bodyWaitMilliseconds!))
            && (event.queueWaitMilliseconds == nil || (0...1_000_000_000).contains(event.queueWaitMilliseconds!))
            && (event.modelSlotWaiters == nil || (0...10_000).contains(event.modelSlotWaiters!))
    }

    static let modelFailureFileLimit = 512 * 1_024

    private func loadModelFailures(now: Date) throws -> [ModelFailureRecord] {
        guard FileManager.default.fileExists(atPath: modelFailuresURL.path) else { return [] }
        let records = try JSONDecoder().decode([ModelFailureRecord].self, from: boundedData(modelFailuresURL, maximum: Self.modelFailureFileLimit))
        guard records.count <= 32, records.allSatisfy(\.valid) else { throw NativeStoreError.invalidActivity }
        return records.filter { $0.date >= now.addingTimeInterval(-7 * 86400) && $0.date <= now.addingTimeInterval(60) }
    }

    func modelFailures(messageID: String, now: Date = Date()) throws -> [ModelFailureRecord] {
        let key = String(try JunkIdentity.key(messageID).prefix(12))
        return try locked { try loadModelFailures(now: now).filter { $0.traceID == key } }
    }

    func recordModelFailure(traceID: String, attempt: Int, policyRevision: String,
                            metrics: ModelRequestMetrics, reply: String, now: Date = Date(), bundle: Bundle = .main) throws {
        let bytes = Data(reply.utf8)
        let record = ModelFailureRecord(date: now, traceID: traceID, attempt: attempt, policyRevision: policyRevision,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String, metrics: metrics,
            replyUTF8Base64: Data(bytes.prefix(8192)).base64EncodedString(), replyTruncated: bytes.count > 8192,
            replySHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        guard record.valid else { throw NativeStoreError.invalidActivity }
        try locked {
            // This expendable diagnostic cache must not become permanently
            // unwritable because an earlier diagnostic file was interrupted.
            var records = (try? loadModelFailures(now: now)) ?? []
            records.append(record)
            records = Array(records.suffix(32))
            let encoder = JSONEncoder()
            var data = try encoder.encode(records)
            while data.count > Self.modelFailureFileLimit && records.count > 1 {
                records.removeFirst(); data = try encoder.encode(records)
            }
            guard data.count <= Self.modelFailureFileLimit else { throw NativeStoreError.invalidActivity }
            try data.write(to: modelFailuresURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: modelFailuresURL.path)
        }
    }

    static let diagnosticFileLimit = 1_024 * 1_024
    private func logURL(_ index: Int) -> URL { directory.appendingPathComponent(index == 0 ? "diagnostic.jsonl" : "diagnostic.\(index).jsonl") }

    /// Shared structured records work without system archive access. This read
    /// holds the same lock as writers and never returns arbitrary file contents.
    func diagnosticEvents(now: Date = Date()) throws -> [NativeActivity] {
        let snapshots: [Data] = try locked {
            try (0...2).reversed().filter { FileManager.default.fileExists(atPath: logURL($0).path) }
                .map { try boundedData(logURL($0), maximum: Self.diagnosticFileLimit) }
        }
        // Parse after releasing the action/settings lock. Support export must
        // not keep an incoming callback waiting while decoding log history.
        var events: [NativeActivity] = []
        for data in snapshots {
            for line in data.split(separator: 10) {
                guard let event = try? JSONDecoder().decode(NativeActivity.self, from: Data(line)),
                      Self.validEvent(event), event.date >= now.addingTimeInterval(-7 * 86400), event.date <= now.addingTimeInterval(60) else { continue }
                events.append(event)
            }
        }
        return Array(events.suffix(2_000))
    }

    private func appendDiagnostic(_ event: NativeActivity) throws {
        let manager = FileManager.default
        for index in 0...2 where manager.fileExists(atPath: logURL(index).path) {
            let date = try logURL(index).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            if date < Date().addingTimeInterval(-7 * 86400) { try manager.removeItem(at: logURL(index)) }
        }
        let line = try JSONEncoder().encode(event) + Data([10])
        guard line.count <= Self.diagnosticFileLimit else { throw NativeStoreError.invalidActivity }
        let size = (try? logURL(0).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size + line.count > Self.diagnosticFileLimit {
            if manager.fileExists(atPath: logURL(2).path) { try manager.removeItem(at: logURL(2)) }
            for index in (0...1).reversed() where manager.fileExists(atPath: logURL(index).path) {
                try manager.moveItem(at: logURL(index), to: logURL(index + 1))
            }
        }
        if !manager.fileExists(atPath: logURL(0).path) { manager.createFile(atPath: logURL(0).path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let handle = try FileHandle(forWritingTo: logURL(0))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL(0).path)
    }

    func record(outcome: String, category: String, processed: Bool = false, junkRequested: Bool = false,
                traceID: String? = nil, receivedCallback: Bool = false, attempt: Int? = nil,
                failureDomain: String? = nil, failureCode: Int? = nil, modelMetrics: ModelRequestMetrics? = nil,
                bodyWaitMilliseconds: Int? = nil, queueWaitMilliseconds: Int? = nil,
                modelSlotBusy: Bool? = nil, modelSlotWaiters: Int? = nil, bundle: Bundle = .main) throws {
        try locked {
            var event = NativeActivity(outcome: outcome, category: category, traceID: traceID,
                attempt: attempt, failureDomain: failureDomain, failureCode: failureCode,
                modelMetrics: modelMetrics, bodyWaitMilliseconds: bodyWaitMilliseconds)
            event.build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            event.channel = bundle.object(forInfoDictionaryKey: "MailFilterDistribution") as? String
            event.queueWaitMilliseconds = queueWaitMilliseconds
            event.modelSlotBusy = modelSlotBusy
            event.modelSlotWaiters = modelSlotWaiters
            guard Self.validEvent(event) else { throw NativeStoreError.invalidActivity }
            var activity = try loadActivity()
            if outcome == "extensionStarted" { activity.lastExtensionStart = event }
            if processed { activity.processed += 1 }
            if junkRequested { activity.junkRequested += 1 }
            if receivedCallback {
                activity.receivedCallbacks = (activity.receivedCallbacks ?? 0) + 1
                activity.lastCallback = Date()
            }
            activity.recent.insert(event, at: 0)
            activity.recent = Array(activity.recent.prefix(NativeActivityLog.maximumRecent))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(activity)
            while data.count > NativeActivityLog.maximumBytes && !activity.recent.isEmpty {
                activity.recent.removeLast(min(50, activity.recent.count))
                data = try encoder.encode(activity)
            }
            guard data.count <= NativeActivityLog.maximumBytes else { throw NativeStoreError.invalidActivity }
            try data.write(to: activityURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activityURL.path)
            // File history supplements activity; failure must not discard an
            // otherwise valid activity record or change a classification result.
            try? appendDiagnostic(event)
        }
    }

    // Called only after the user explicitly chooses to erase private application data.
    func eraseApplicationData() throws {
        try locked {
            for url in [settingsURL, activityURL, modelFailuresURL, directory.appendingPathComponent("migration-backup.json"), directory.appendingPathComponent("junk-protection.json"), directory.appendingPathComponent("junk-protection.json.lock")] + (0...2).map(logURL) {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
    }

    private func loadSettings() throws -> NativeSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return NativeSettings() }
        do {
            let settings = try JSONDecoder().decode(NativeSettings.self, from: boundedData(settingsURL, maximum: 16 * 1_024 * 1_024))
            try settings.validate()
            return settings
        } catch { throw NativeStoreError.invalidSettings }
    }

    private func loadActivity() throws -> NativeActivityLog {
        guard FileManager.default.fileExists(atPath: activityURL.path) else { return NativeActivityLog() }
        do {
            let activity = try JSONDecoder().decode(NativeActivityLog.self, from: boundedData(activityURL, maximum: NativeActivityLog.maximumBytes))
            guard activity.schemaVersion == 1, activity.processed >= 0, activity.junkRequested >= 0, activity.recent.count <= NativeActivityLog.maximumRecent,
                  (activity.receivedCallbacks ?? 0) >= 0,
                  activity.lastExtensionStart.map({ $0.outcome == "extensionStarted" && Self.validEvent($0) }) != false,
                  activity.recent.allSatisfy(Self.validEvent) else { throw NativeStoreError.invalidActivity }
            return activity
        } catch { throw NativeStoreError.invalidActivity }
    }

    private func boundedData(_ url: URL, maximum: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximum else { throw NativeStoreError.invalidSettings }
        let data = try Data(contentsOf: url)
        guard data.count <= maximum else { throw NativeStoreError.invalidSettings }
        return data
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= 20 * 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("settings.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NativeStoreError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw NativeStoreError.busy }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
