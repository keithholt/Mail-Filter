import Foundation
import AppKit
import Darwin

struct NativeCheckFailure: Error { let name: String }

@main
@MainActor
struct NativeChecks {
    static var count = 0
    static func require(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        if try !value() { throw NativeCheckFailure(name: name) }
        count += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        var failed = false
        do { try operation() } catch { failed = true }
        try require(failed, name)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try NativeStorage.directory(mode: "local-development", group: nil, userHome: root) { _ in
            preconditionFailure("A local build must not request an App Group")
        }
        try require(local == root.appendingPathComponent(NativeStorage.localRelativePath, isDirectory: true), "local host and extension use a fixed private account-relative store")
        try require(try NativeStorage.accountHome().path == FileManager.default.homeDirectoryForCurrentUser.path, "account home resolves outside a container")
        try rejects("production group denial has no local fallback") {
            _ = try NativeStorage.directory(mode: "app-group", group: "EXAMPLETEAM.org.mail-filter.shared", userHome: root) { _ in nil }
        }
        try rejects("unknown storage mode never chooses a fallback") {
            _ = try NativeStorage.directory(mode: "unsupported", group: nil, userHome: root) { _ in root }
        }
        let localStore = SharedStore(directory: local)
        try localStore.setPaused(true)
        try require(try SharedStore(directory: local).settings().paused, "two local participants share persistent setup and pause state")
        let privateMode = try FileManager.default.attributesOfItem(atPath: local.path)[.posixPermissions] as? NSNumber
        try require(privateMode?.intValue == 0o700, "local shared folder remains private to the account")
        let store = SharedStore(directory: root.appendingPathComponent("shared"))
        try require(try store.settings().configuration == nil, "fresh install inactive until configured")
        try require(try !store.settings().paused, "Enable filtering defaults on for a fresh setup")
        var settings = NativeSettings()
        settings.inventory = [NativeAccount(id: "first", name: "Same name", addresses: ["me@example.com"]), NativeAccount(id: "second", name: "Same name", addresses: ["me@work.example"])]
        settings.selectedAccountIDs = ["first"]
        let accounts = settings.inventory.map { FilteringAccount(id: $0.id, name: $0.id, addresses: $0.addresses) }
        settings.configuration = try FilteringConfiguration.make(selectedNames: ["first"], inventory: accounts, rules: "Filter political solicitations only.", evidenceTerms: ["election"])
        try store.save(settings)
        let snapshot = try store.settings()
        try require(snapshot.configuration!.selectedRecipientAddresses == ["me@example.com"], "stable-ID selection distinguishes same-name accounts")
        try require(snapshot.configuration!.ownAddresses.count == 2, "unselected own accounts protected")
        try require(snapshot.configuration!.mode == "apply", "native default moves political matches")
        let id = "<one@example.org>"
        try require(try store.finish(messageID: id, revision: snapshot.revision, decision: .notPolitical, evidence: "election") == .notPolitical, "negative never reserves")
        try require(try !store.protection.contains(messageID: id), "negative has no recovery side effect")
        try require(try store.finish(messageID: id, revision: snapshot.revision, decision: .political, evidence: nil) == .notPolitical, "unverified positive never moves")
        try store.setPaused(true)
        try require(try store.finish(messageID: id, revision: snapshot.revision, decision: .political, evidence: "election") == .settingsChanged, "pause during generation cancels Junk request")
        try require(try !store.protection.contains(messageID: id), "cancelled generation remains eligible")
        try store.setPaused(false)
        let resumed = try store.settings()
        try require(resumed.revision != snapshot.revision && !resumed.paused, "resume invalidates in-memory generation cache")
        try require(try store.finish(messageID: id, revision: snapshot.revision, decision: .political, evidence: "election") == .settingsChanged, "old result cannot apply after resume")
        try require(try store.finish(messageID: id, revision: resumed.revision, decision: .political, evidence: "election") == .junkRequested, "current verified result reserved on disk before action")
        let relaunched = SharedStore(directory: store.directory)
        try require(try relaunched.protects("one@example.org", configuration: resumed.configuration!), "restart and bracket normalization preserve returned messages")
        try require(try relaunched.finish(messageID: id, revision: resumed.revision, decision: .political, evidence: "election") == .protected, "same ID cannot move again")
        var preview = resumed
        preview.revision = UUID().uuidString
        preview.configuration = try FilteringConfiguration.make(selectedNames: ["first"], inventory: accounts, rules: "Filter political solicitations only.", evidenceTerms: ["election"], mode: "dry-run")
        try store.save(preview)
        try require(try store.finish(messageID: "preview@example.org", revision: preview.revision, decision: .political, evidence: "election") == .previewPolitical, "saved preview immediately changes next callback")
        try require(try !store.protection.contains(messageID: "preview@example.org"), "preview never poisons moving mode")
        try require(try store.finish(messageID: "new@example.org", revision: resumed.revision, decision: .political, evidence: "election") == .settingsChanged, "settings edited mid-generation reject stale result")
        let old = JunkProtection(url: root.appendingPathComponent("old/junk-protection.json"))
        _ = try old.reserve(messageID: "restored@example.org")
        try store.importProtection(from: root.appendingPathComponent("old/junk-protection.json"))
        try require(try store.protection.contains(messageID: "restored@example.org"), "prototype protection migration")
        try require(try store.protection.contains(messageID: id), "migration merges rather than replacing native protection")
        try store.record(outcome: "junkRequested", category: "", processed: true, junkRequested: true)
        try store.record(outcome: "notPolitical", category: "", processed: true)
        let activity = try relaunched.activity()
        try require(activity.processed == 2 && activity.junkRequested == 1, "persistent activity counts requests accurately")
        for _ in 0..<510 { try store.record(outcome: "skipped", category: "selfMail") }
        try require(try store.activity().recent.count == 500, "activity history bounded")
        let savedText = try String(contentsOf: store.activityURL, encoding: .utf8)
        try require(!savedText.contains("example.org") && !savedText.contains("Same name") && !savedText.contains("political solicitations"), "activity contains no personal fields or rules")
        let mode = try FileManager.default.attributesOfItem(atPath: store.settingsURL.path)[.posixPermissions] as? NSNumber
        try require(mode?.intValue == 0o600, "private settings permissions")
        try Data("corrupt".utf8).write(to: store.settingsURL)
        try rejects("corrupt settings prevent decisions") { _ = try store.finish(messageID: "new@example.org", revision: preview.revision, decision: .political, evidence: "election") }
        try require(try String(contentsOf: store.settingsURL, encoding: .utf8) == "corrupt", "corrupt configuration not reset on read")
        var unsupported = preview
        unsupported.schemaVersion = 999
        let previousData = try JSONEncoder().encode(unsupported)
        try previousData.write(to: store.settingsURL)
        try rejects("unsupported settings format is reported instead of reset") { _ = try store.settings() }
        try require(try Data(contentsOf: store.settingsURL) == previousData, "unsupported settings preserved byte for byte")
        try store.save(preview)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("bad-protection.json"))
        try rejects("corrupt migration fails without clearing old protection") { try store.importProtection(from: root.appendingPathComponent("bad-protection.json")) }
        try require(try store.protection.contains(messageID: id), "failed migration preserves current protection")
        let migrationConfig = try FilteringConfiguration.make(selectedNames: ["first"], inventory: accounts, rules: "Updated political rules", evidenceTerms: ["election"])
        let migrated = try store.importSetup(configuration: migrationConfig, protectionFile: root.appendingPathComponent("old/junk-protection.json"))
        try require(migrated.configuration?.rules == "Updated political rules", "migration replaces policy only after valid protection")
        try require(try store.protection.contains(messageID: id) && store.protection.contains(messageID: "restored@example.org"), "migration preserves both generations of recovery records")
        let migrationRevision = migrated.revision
        try rejects("damaged setup migration cannot replace current policy") {
            _ = try store.importSetup(configuration: migrationConfig, protectionFile: root.appendingPathComponent("bad-protection.json"))
        }
        try require(try store.settings().revision == migrationRevision, "failed migration leaves saved policy untouched")
        let inheritedHash = try JunkIdentity.hash(["first", "cli-restored@example.org"])
        var inheritedSettings = try store.settings()
        inheritedSettings.configuration = try FilteringConfiguration.make(selectedNames: ["first"], inventory: accounts, rules: "Rules", evidenceTerms: ["election"], protectedCLIIdentities: [inheritedHash])
        try store.save(inheritedSettings)
        let mergedSettings = try store.importSetup(configuration: migrationConfig, protectionFile: nil)
        try require(mergedSettings.configuration!.protectedCLIIdentities == [inheritedHash], "import preserves earlier inherited CLI protection")
        _ = try MailAutomation.script(AccountInventory.script, execute: false)
        count += 1
        try removalFixtures(root: root)
        try store.eraseApplicationData()
        try require(try store.settings().configuration == nil, "erasing chosen app data leaves setup inactive")
        try require(try store.activity().recent.isEmpty, "chosen data erase removes private activity")
        let oldActivity = try JSONDecoder().decode(NativeActivityLog.self, from: Data("{\"schemaVersion\":1,\"processed\":1,\"junkRequested\":1,\"recent\":[]}".utf8))
        try require(oldActivity.processed == 1 && oldActivity.receivedCallbacks == nil, "version-5 activity remains readable without resetting totals")
        let diagnosticStore = SharedStore(directory: root.appendingPathComponent("diagnostic-stages"))
        try diagnosticStore.record(outcome: "callbackReceived", category: "bodyReady", traceID: "012345abcdef", receivedCallback: true)
        try diagnosticStore.record(outcome: "analysisStarted", category: "onDeviceModel", traceID: "012345abcdef")
        let stages = try diagnosticStore.activity()
        try require(stages.receivedCallbacks == 1 && stages.lastCallback != nil, "callbacks are persisted before classification finishes")
        try require(stages.recent.count == 2 && stages.recent.allSatisfy({ $0.traceID == "012345abcdef" }), "opaque trace connects callback and analysis stages")
        try require(stages.processed == 0 && stages.junkRequested == 0, "diagnostic stages do not claim classifications or moves")
        let selectedID = "selected@example.com"
        let selectedKey = String(try JunkIdentity.key(selectedID).prefix(12))
        try diagnosticStore.record(outcome: "review", category: "invalidModelResponse", traceID: selectedKey, attempt: 3)
        let history = MessageDiagnostics.automaticHistory(messageID: selectedID, activity: try diagnosticStore.activity())
        try require(history.contains("review invalidModelResponse attempt=3") && !history.contains("onDeviceModel"), "selected analysis connects the original failure for exactly that email")
        _ = try MailAutomation.script(MessageDiagnostics.selectedMessageScript, execute: false)
        count += 1
        try require(ToolError("Select one message in Mail.").localizedDescription == "Select one message in Mail.", "GUI errors preserve the actionable tool message")
        let diagnosticReply = MessageDiagnostics.invalidResponse("I cannot classify this email.", error: ToolError("Invalid classification JSON"))
        try require(diagnosticReply.contains("Invalid classification JSON") && diagnosticReply.contains("I cannot classify this email."), "read-only model failure shows its actual reply and parsing error")
        try diagnosticStore.record(outcome: "retryScheduled", category: "modelDecodingFailure", traceID: "012345abcdef",
                                   attempt: 2, failureDomain: "FoundationModels.Test", failureCode: 1008)
        let failure = try diagnosticStore.activity().recent[0]
        try require(failure.attempt == 2 && failure.failureDomain == "FoundationModels.Test" && failure.failureCode == 1008,
                    "attempt and specific error metadata survive persistence without message text")
        let upgradeStore = SharedStore(directory: root.appendingPathComponent("word-upgrade"))
        var legacyWords = NativeSettings()
        legacyWords.inventory = accounts.map { NativeAccount(id: $0.id, name: $0.name, addresses: $0.addresses) }
        legacyWords.selectedAccountIDs = ["first"]
        legacyWords.paused = true
        legacyWords.configuration = try FilteringConfiguration.make(selectedNames: ["first"], inventory: accounts,
            rules: "Preserve my custom filtering instructions.", evidenceTerms: PoliticalVerificationWords.previousDefaults, mode: "dry-run")
        try upgradeStore.save(legacyWords)
        _ = try upgradeStore.protection.reserve(messageID: "restored@example.org")
        try require(try upgradeStore.updateStandardVerificationWords(), "original standard word list receives requested additions")
        let upgradedWords = try upgradeStore.settings()
        try require(upgradedWords.configuration!.evidenceTerms == PoliticalVerificationWords.previousDefaults + PoliticalVerificationWords.additions,
                    "MAGA, candidate/donation and plurals are appended without removing old vocabulary")
        try require(upgradedWords.configuration!.rules == legacyWords.configuration!.rules
                    && upgradedWords.configuration!.mode == "dry-run" && upgradedWords.paused
                    && upgradedWords.inventory == legacyWords.inventory && upgradedWords.selectedAccountIDs == legacyWords.selectedAccountIDs,
                    "word update preserves custom rules, accounts, preview and pause")
        try require(try upgradeStore.protection.contains(messageID: "restored@example.org"), "word update preserves recovery protection")
        try require(upgradedWords.revision != legacyWords.revision, "updated words invalidate in-flight old-policy results")
        try require(try !upgradeStore.updateStandardVerificationWords(), "word update is idempotent")
        var customWords = upgradedWords
        customWords.configuration = try FilteringConfiguration.make(selectedNames: ["first"], inventory: accounts,
            rules: "Custom", evidenceTerms: ["election", "my custom political phrase"])
        try upgradeStore.save(customWords)
        try require(try !upgradeStore.updateStandardVerificationWords()
                    && upgradeStore.settings().configuration!.evidenceTerms == ["election", "my custom political phrase"],
                    "custom verification lists are never silently replaced")
        let source = Data("Content-Type: text/plain; charset=utf-8\r\n\r\nSupport our election campaign".utf8)
        let selected = MessageDiagnostics.Selection(message: MailMessage(accountID: "first", account: "PRIVATE INVENTORY NAME", id: 42,
            messageID: selectedID, subject: "Synthetic campaign", sender: "advertiser@example.com", body: "", truncated: false), source: source)
        let export = SelectedEmailReport(selection: selected, settings: legacyWords, activity: try diagnosticStore.activity(),
            analysis: "Selected synthetic analysis", appBuild: "11", extensionBuild: "11")
        let exportURL = root.appendingPathComponent("selected-email-report.json")
        try export.write(to: exportURL)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as! [String: Any]
        try require(Data(base64Encoded: object["sourceBase64"] as! String) == source && object["extractedBody"] as? String == "Support our election campaign", "selected export preserves reproducible source and extracted model input")
        try require((object["automaticHistory"] as! [[String: Any]]).count == 1 && export.currentReadOnlyAnalysis == "Selected synthetic analysis", "selected export contains only same-email history and supplied analysis")
        try require(object["inventory"] == nil && !(try String(contentsOf: exportURL, encoding: .utf8)).contains("PRIVATE INVENTORY NAME"), "selected export excludes account inventory")
        try require((try FileManager.default.attributesOfItem(atPath: exportURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "selected email export is owner-readable only")
        let brokenSelection = MessageDiagnostics.Selection(message: selected.message, source: Data("not a MIME message".utf8))
        let brokenExport = SelectedEmailReport(selection: brokenSelection, settings: legacyWords, activity: try diagnosticStore.activity(), analysis: nil, appBuild: "11", extensionBuild: "11")
        try require(brokenExport.extractionError == "malformedHeaders" && brokenExport.extractedBody == nil && brokenExport.messageID == selectedID,
                    "body extraction failures can still be exported with identity and source")
        print("Passed \(count) native settings, hot reload, migration, activity and removal checks; no model generation or real Mail/installer/removal actions")
    }

    static func removalFixtures(root: URL) throws {
        let applications = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try require(try UninstallPlan.applicationsToRemove(applications: applications).isEmpty, "missing installation requires no destructive action")
        let product = applications.appendingPathComponent("Mail-Filter.app/Contents")
        try FileManager.default.createDirectory(at: product, withIntermediateDirectories: true)
        let info = product.appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"org.example.unrelated"], format: .xml, options: 0).write(to: info)
        try rejects("unrelated same-name application never removed") { _ = try UninstallPlan.applicationsToRemove(applications: applications) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":UninstallPlan.appIdentifier], format: .xml, options: 0).write(to: info)
        try require(try UninstallPlan.applicationsToRemove(applications: applications) == [product.deletingLastPathComponent()], "recognized product produces bounded Trash target")
        let fakeUninstaller = applications.appendingPathComponent("Uninstall Mail-Filter.app")
        try FileManager.default.createSymbolicLink(at: fakeUninstaller, withDestinationURL: product.deletingLastPathComponent())
        try rejects("symbolic-link target refused before any removal") { _ = try UninstallPlan.applicationsToRemove(applications: applications) }
        try require(FileManager.default.fileExists(atPath: info.path), "failed plan leaves validated app untouched")
        let home = root.appendingPathComponent("fake-home")
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let path = agents.appendingPathComponent("org.mail-filter.agent.plist")
        let unrelated: [String: Any] = ["Label":"org.example.other", "ProgramArguments":["/usr/bin/true"]]
        try PropertyListSerialization.data(fromPropertyList: unrelated, format: .xml, options: 0).write(to: path)
        var unloaded = false
        try rejects("unrelated timer cannot be removed") { try UninstallPlan.removeLegacyTimer(home: home) { unloaded = true } }
        try require(!unloaded && FileManager.default.fileExists(atPath: path.path), "unrelated timer preserved without unload")
        let valid: [String: Any] = ["Label":"org.mail-filter.agent", "ProgramArguments":["/synthetic/mail-filter", "--skip-processed"]]
        try PropertyListSerialization.data(fromPropertyList: valid, format: .xml, options: 0).write(to: path)
        try UninstallPlan.removeLegacyTimer(home: home) { unloaded = true }
        try require(unloaded && !FileManager.default.fileExists(atPath: path.path), "recognized fixture timer unloaded before removing installation file")
        try require(FileManager.default.fileExists(atPath: root.appendingPathComponent("old/junk-protection.json").path), "removal never clears old probe protection")
        let etc = root.appendingPathComponent("etc")
        let paths = etc.appendingPathComponent("paths.d")
        try FileManager.default.createDirectory(at: paths, withIntermediateDirectories: true)
        try require(try UninstallPlan.commandLinePathToRemove(etc: etc) == nil, "missing PATH entry is a normal uninstall")
        let pathEntry = paths.appendingPathComponent("org.mail-filter.command-line")
        try Data("/unrelated/tool\n".utf8).write(to: pathEntry)
        try rejects("unrelated PATH entry is preserved") { _ = try UninstallPlan.commandLinePathToRemove(etc: etc) }
        try require(try String(contentsOf: pathEntry, encoding: .utf8) == "/unrelated/tool\n", "PATH validation does not edit files")
        try Data((UninstallPlan.commandLineDirectory + "\n").utf8).write(to: pathEntry)
        try require(try UninstallPlan.commandLinePathToRemove(etc: etc) == pathEntry, "owned PATH entry produces one bounded removal target")
        let savedPath = paths.appendingPathComponent("saved-path")
        try FileManager.default.moveItem(at: pathEntry, to: savedPath)
        try FileManager.default.createSymbolicLink(at: pathEntry, withDestinationURL: savedPath)
        try rejects("redirected PATH entry is not removed") { _ = try UninstallPlan.commandLinePathToRemove(etc: etc) }
        try require(FileManager.default.fileExists(atPath: savedPath.path), "redirected PATH target remains intact")
    }
}
