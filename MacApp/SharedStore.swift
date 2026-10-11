import Foundation
import Darwin

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
}

struct NativeActivityLog: Codable {
    var schemaVersion = 1
    var processed = 0
    var junkRequested = 0
    var recent: [NativeActivity] = []
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

    func record(outcome: String, category: String, processed: Bool = false, junkRequested: Bool = false) throws {
        try locked {
            var activity = try loadActivity()
            if processed { activity.processed += 1 }
            if junkRequested { activity.junkRequested += 1 }
            activity.recent.insert(NativeActivity(outcome: outcome, category: category), at: 0)
            activity.recent = Array(activity.recent.prefix(100))
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
            let activity = try JSONDecoder().decode(NativeActivityLog.self, from: boundedData(activityURL, maximum: 256 * 1_024))
            guard activity.schemaVersion == 1, activity.processed >= 0, activity.junkRequested >= 0, activity.recent.count <= 100,
                  activity.recent.allSatisfy({ $0.outcome.count <= 80 && $0.category.count <= 100 }) else { throw NativeStoreError.invalidActivity }
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
