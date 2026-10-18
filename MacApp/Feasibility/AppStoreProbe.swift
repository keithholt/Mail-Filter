import AppKit
import ApplicationServices
import FoundationModels
import OSLog

/// Read-only Mail metadata and synthetic storage checks. Never installs an
/// extension, sends mail, changes filtering settings or returns a Mail action.
@main
@MainActor
struct AppStoreProbe {
    static func errorCode(_ error: Error) -> [String: Any] {
        let value = error as NSError
        return ["domain": value.domain, "code": value.code]
    }

    static func main() async {
        var report: [String: Any] = [:]
        let arguments = Set(CommandLine.arguments.dropFirst())
        let home = FileManager.default.homeDirectoryForCurrentUser
        let containerized = home.path.contains("/Library/Containers/")
        report["containerizedHome"] = containerized
        report["bundleID"] = Bundle.main.bundleIdentifier ?? "unavailable"
        let logger = Logger(subsystem: "org.mail-filter.feasibility", category: "Synthetic")
        logger.notice("Synthetic feasibility event; no email content")
        report["loggerAPICallCompleted"] = true
        do {
            _ = try OSLogStore(scope: .currentProcessIdentifier)
            report["currentProcessLogStoreOpened"] = true
        } catch { report["currentProcessLogStoreError"] = errorCode(error) }

        // A sandboxed helper uses its container; a baseline uses only temp.
        // Both paths contain exclusively a freshly generated synthetic fixture.
        let base = containerized
            ? home.appendingPathComponent("Library/Application Support")
            : FileManager.default.temporaryDirectory
        let fixture = base.appendingPathComponent("MailFilterFeasibility-" + UUID().uuidString)
        do {
            let store = SharedStore(directory: fixture)
            let inventory = [FilteringAccount(id: "synthetic", name: "Synthetic", addresses: ["owner@example.com", "alias@example.com"])]
            var settings = NativeSettings()
            settings.inventory = [.init(id: "synthetic", name: "Synthetic", addresses: inventory[0].addresses)]
            settings.selectedAccountIDs = ["synthetic"]
            settings.configuration = try FilteringConfiguration.make(selectedNames: ["Synthetic"], inventory: inventory,
                rules: "Political solicitations only.", evidenceTerms: ["campaign", "Paid for by"], mode: "dry-run")
            try store.save(settings)
            try store.record(outcome: "review", category: "syntheticCheck", traceID: "012345abcdef")
            let saved = try store.settings()
            let loadedActivity = try store.activity()
            report["syntheticSettingsRoundTrip"] = saved.configuration?.mode == "dry-run"
            report["syntheticActivityRoundTrip"] = loadedActivity.recent.first?.category == "syntheticCheck"
            let file = fixture.appendingPathComponent("diagnostic.jsonl")
            try Data("{\"event\":\"syntheticCheck\"}\n".utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            report["privateFileLogging"] = try String(contentsOf: file, encoding: .utf8).contains("syntheticCheck")
            try FileManager.default.removeItem(at: fixture)
        } catch { report["storageError"] = errorCode(error) }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        switch model.availability {
        case .available: report["modelAvailability"] = "available"
        case .unavailable(.appleIntelligenceNotEnabled): report["modelAvailability"] = "notEnabled"
        case .unavailable(.deviceNotEligible): report["modelAvailability"] = "deviceNotEligible"
        case .unavailable(.modelNotReady): report["modelAvailability"] = "notReady"
        case .unavailable: report["modelAvailability"] = "unavailable"
        @unknown default: report["modelAvailability"] = "unknown"
        }
        if arguments.contains("--synthetic-model"), case .available = model.availability {
            do {
                let message = MailMessage(accountID: "synthetic", account: "Synthetic", id: 1,
                    messageID: "synthetic@example.com", subject: "Support our election campaign",
                    sender: "Example campaign <appeals@example.org>", body: "Please donate to our election campaign. Paid for by Example Committee.", truncated: false)
                let result = try await AnalysisDeadline.run(seconds: 20) {
                    try await PoliticalModel.classify(message, rules: "Classify campaign fundraising as political; receipts and personal mail as not-political.", model: model)
                }
                report["syntheticModelDecision"] = result.classification.decision.rawValue
            } catch {
                let details = ModelFailureDetails.describe(error)
                report["syntheticModelError"] = ["category": details.category, "domain": details.domain, "code": details.code]
            }
        }

        if arguments.contains("--mail-metadata") {
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
            report["mailVisibleAsRunning"] = running
            if running {
                let descriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
                // Preflight without prompting. A pending TCC decision remains an
                // explicit untested gate instead of generating consent dialogs.
                let permission = AEDeterminePermissionToAutomateTarget(descriptor.aeDesc, typeWildCard, typeWildCard,
                    arguments.contains("--request-mail-permission"))
                report["mailAutomationPreflight"] = permission
                if permission == noErr {
                    let script = NSAppleScript(source: """
                    with timeout of 8 seconds
                        tell application id "com.apple.mail"
                            set accountCount to count of accounts
                            set chosen to selection
                            set selectedCount to count of chosen
                            set sourceLength to -1
                            if selectedCount is 1 then set sourceLength to count of characters of (source of item 1 of chosen)
                            return {accountCount, selectedCount, sourceLength}
                        end tell
                    end timeout
                    """)!
                    var error: NSDictionary?
                    let response = script.executeAndReturnError(&error)
                    if let error { report["mailMetadataErrorCode"] = error[NSAppleScript.errorNumber] ?? 0 }
                    else {
                        report["mailAccountCountRead"] = response.atIndex(1)?.int32Value ?? -1
                        report["mailSelectionCountRead"] = response.atIndex(2)?.int32Value ?? -1
                        report["mailSelectedSourceLength"] = response.atIndex(3)?.int32Value ?? -1
                    }
                }
            }
        }

        let encoderOptions: JSONSerialization.WritingOptions = [.sortedKeys]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: encoderOptions) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
