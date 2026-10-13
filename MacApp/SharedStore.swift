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
}

struct NativeSettings: Codable {
    var schemaVersion = 1
    var revision = UUID().uuidString
    var paused = false
    var inventory: [NativeAccount] = []
    var selectedAccountIDs: [String] = []
    var configuration: FilteringConfiguration?

    func validate() throws {
        guard schemaVersion == 1, UUID(uuidString: revision) != nil,
              inventory.count <= 1_024, selectedAccountIDs.count <= 1_024,
              Set(inventory.map(\.id)).count == inventory.count,
              inventory.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 256 && !$0.name.isEmpty && $0.name.count <= 500 && $0.addresses.count <= 1_024 }),
              inventory.flatMap(\.addresses).allSatisfy({ $0.count <= 320 }),
              Set(selectedAccountIDs).isSubset(of: Set(inventory.map(\.id))) else { throw NativeStoreError.invalidSettings }
        try configuration?.validate()
    }
}

struct NativeActivity: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let outcome: String
    let category: String
    var traceID: String? = nil
    var attempt: Int? = nil
    var failureDomain: String? = nil
    var failureCode: Int? = nil
}

struct NativeActivityLog: Codable {
    static let maximumRecent = 500
    var schemaVersion = 1
    var processed = 0
    var junkRequested = 0
    var recent: [NativeActivity] = []
    // Optional fields keep existing version-5 activity files compatible.
    var receivedCallbacks: Int? = nil
    var lastCallback: Date? = nil
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
    var protection: JunkProtection { JunkProtection(url: directory.appendingPathComponent("junk-protection.json")) }

    init(directory: URL) { self.directory = directory }

    static func production(bundle: Bundle = .main) throws -> SharedStore {
        let mode = bundle.object(forInfoDictionaryKey: "MailFilterStorageMode") as? String ?? "app-group"
        let group = bundle.object(forInfoDictionaryKey: "MailFilterAppGroup") as? String
        let directory = try NativeStorage.directory(mode: mode, group: group, userHome: NativeStorage.accountHome()) {
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
            guard saved == previous || saved == version9 || saved == version11 else { return false }
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
    func updateStandardPrompt(_ rules: String, replacingDigest: String = "818fba6fb1f6c4fc2ae6869b24ba55e50bf356ee28d86eb07c161ce912264968") throws -> Bool {
        try locked {
            var settings = try loadSettings()
            guard let original = settings.configuration else { return false }
            let digest = SHA256.hash(data: Data(original.rules.trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map { String(format: "%02x", $0) }.joined()
            guard digest == replacingDigest, original.rules != rules else { return false }
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

    func protects(_ messageID: String, configuration: FilteringConfiguration) throws -> Bool {
        try locked {
            try JunkIdentity.protectedByCLI(messageID: messageID, accountIDs: configuration.legacyAccountIDs,
                                          identities: configuration.protectedCLIIdentities) || protection.contains(messageID: messageID)
        }
    }

    func finish(messageID: String, revision: String, decision: Classification.Decision, evidence: String?) throws -> NativeOutcome {
        try locked {
            let current = try loadSettings()
            guard !current.paused, current.revision == revision, let configuration = current.configuration else { return .settingsChanged }
            guard decision == .political, let evidence, !evidence.isEmpty else { return .notPolitical }
            if try JunkIdentity.protectedByCLI(messageID: messageID, accountIDs: configuration.legacyAccountIDs,
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

    func record(outcome: String, category: String, processed: Bool = false, junkRequested: Bool = false,
                traceID: String? = nil, receivedCallback: Bool = false, attempt: Int? = nil,
                failureDomain: String? = nil, failureCode: Int? = nil) throws {
        try locked {
            var activity = try loadActivity()
            if processed { activity.processed += 1 }
            if junkRequested { activity.junkRequested += 1 }
            if receivedCallback {
                activity.receivedCallbacks = (activity.receivedCallbacks ?? 0) + 1
                activity.lastCallback = Date()
            }
            activity.recent.insert(NativeActivity(outcome: outcome, category: category, traceID: traceID,
                                                 attempt: attempt, failureDomain: failureDomain, failureCode: failureCode), at: 0)
            activity.recent = Array(activity.recent.prefix(NativeActivityLog.maximumRecent))
            try write(activity, to: activityURL)
        }
    }

    // Called only after the user explicitly chooses to erase private application data.
    func eraseApplicationData() throws {
        try locked {
            for url in [settingsURL, activityURL, directory.appendingPathComponent("junk-protection.json"), directory.appendingPathComponent("junk-protection.json.lock")] {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
    }

    private func loadSettings() throws -> NativeSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return NativeSettings() }
        do {
            let settings = try JSONDecoder().decode(NativeSettings.self, from: boundedData(settingsURL, maximum: 1_024 * 1_024))
            try settings.validate()
            return settings
        } catch { throw NativeStoreError.invalidSettings }
    }

    private func loadActivity() throws -> NativeActivityLog {
        guard FileManager.default.fileExists(atPath: activityURL.path) else { return NativeActivityLog() }
        do {
            let activity = try JSONDecoder().decode(NativeActivityLog.self, from: boundedData(activityURL, maximum: 1_024 * 1_024))
            guard activity.schemaVersion == 1, activity.processed >= 0, activity.junkRequested >= 0, activity.recent.count <= NativeActivityLog.maximumRecent,
                  (activity.receivedCallbacks ?? 0) >= 0,
                  activity.recent.allSatisfy({
                      $0.outcome.count <= 80 && $0.category.count <= 100
                      && ($0.traceID == nil || ($0.traceID!.count == 12 && $0.traceID!.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })))
                      && ($0.attempt == nil || (1...10).contains($0.attempt!))
                      && (($0.failureDomain == nil) == ($0.failureCode == nil))
                      && ($0.failureDomain == nil || ($0.failureDomain!.count <= 200 && $0.failureDomain!.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil))
                  }) else { throw NativeStoreError.invalidActivity }
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
        guard data.count <= 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
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
