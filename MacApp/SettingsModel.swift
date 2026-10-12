import AppKit
import SwiftUI
import FoundationModels
import UniformTypeIdentifiers

@MainActor
final class SettingsModel: ObservableObject {
    @Published var page = "Filtering"
    @Published var advanced = false
    @Published var accounts: [NativeAccount] = []
    @Published var selection = Set<String>()
    @Published var rules = ""
    @Published var evidenceText = ""
    @Published var preview = false
    @Published var paused = false
    @Published var saved = false
    @Published var busy = false
    @Published var message = "Select accounts, save settings, then enable Mail-Filter in Mail."
    @Published var error: String?
    @Published var activity = NativeActivityLog()
    @Published var modelStatus = "Checking Apple Intelligence…"
    @Published var mailRunning = false
    @Published var legacyTimerInstalled = false
    @Published var analyzingSelectedMessage = false
    @Published var selectedAnalysis: String?
    @Published var diagnosticMessage: String?
    @Published var diagnosticReport: String?
    @Published var collectingDiagnostics = false
    private var store: SharedStore?
    private var loaded = NativeSettings()
    init() {
        rules = resource("filter")
        evidenceText = resource("political-evidence")
        do {
            store = try SharedStore.production()
            let wordsUpdated = try store!.updateStandardVerificationWords()
            loaded = try store!.settings()
            applyLoadedSettings()
            if wordsUpdated { message = "Added MAGA, candidate/candidates and donation/donations to the standard verification list. Your other saved settings were preserved." }
        } catch { self.error = error.localizedDescription }
        reloadStatus()
    }

    private func resource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func applyLoadedSettings() {
        accounts = loaded.inventory
        selection = Set(loaded.selectedAccountIDs)
        paused = loaded.paused
        saved = loaded.configuration != nil
        if let configuration = loaded.configuration {
            rules = configuration.rules
            evidenceText = configuration.evidenceTerms.joined(separator: "\n")
            preview = configuration.mode == "dry-run"
            message = "Saved \(preview ? "preview" : "Junk-moving") settings. Enable Mail-Filter in Mail's Extensions settings."
        }
    }

    func reloadStatus() {
        mailRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
        legacyTimerInstalled = FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/org.mail-filter.agent.plist").path)
        switch SystemLanguageModel(guardrails: .permissiveContentTransformations).availability {
        case .available: modelStatus = "Ready"
        case .unavailable(.appleIntelligenceNotEnabled): modelStatus = "Enable Apple Intelligence in System Settings."
        case .unavailable(.deviceNotEligible): modelStatus = "This Mac does not support Apple Intelligence."
        case .unavailable(.modelNotReady): modelStatus = "The on-device model is still downloading or preparing."
        case .unavailable: modelStatus = "The on-device model is unavailable."
        @unknown default: modelStatus = "The on-device model is unavailable."
        }
        do {
            if store == nil { store = try SharedStore.production() }
            activity = try store!.activity()
            paused = try store!.settings().paused
        } catch { self.error = error.localizedDescription }
    }

    func readAccounts() {
        busy = true; error = nil
        defer { busy = false }
        do {
            accounts = try AccountInventory.read()
            let valid = Set(accounts.map(\.id))
            selection.formIntersection(valid)
            if selection.isEmpty, let configuration = loaded.configuration {
                let addresses = Set(configuration.selectedRecipientAddresses)
                selection = Set(accounts.filter { !$0.addresses.map(normalizedEmailAddress).filter(addresses.contains).isEmpty }.map(\.id))
            }
            message = "Mail accounts loaded. Choose the accounts to filter, then Save Settings. Messages were not read."
        } catch {
            self.error = "Couldn't read Mail accounts. Open Mail and allow Mail-Filter under System Settings → Privacy & Security → Automation, then try again."
        }
    }

    func save() {
        error = nil
        do {
            guard let store else { throw NativeStoreError.unavailable }
            let cli = try FilteringConfiguration.cliProtection(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/mail-filter/processed.json"))
            let inherited = Array(Set(cli + (loaded.configuration?.protectedCLIIdentities ?? []))).sorted()
            // Select by stable IDs, so identically named accounts remain distinct.
            let inventory = accounts.map { FilteringAccount(id: $0.id, name: $0.id, addresses: $0.addresses) }
            let configuration = try FilteringConfiguration.make(selectedNames: selection.sorted(), inventory: inventory, rules: rules,
                evidenceTerms: politicalEvidenceTerms(evidenceText), mode: preview ? "dry-run" : "apply", protectedCLIIdentities: inherited)
            let current = try store.settings()
            var settings = current
            settings.revision = UUID().uuidString
            settings.configuration = configuration
            settings.inventory = accounts
            settings.selectedAccountIDs = selection.sorted()
            try store.save(settings)
            loaded = settings; saved = true
            message = "Settings saved. New messages use these settings without a restart. You can close this window."
            reloadStatus()
        } catch let category as FilteringConfigurationError {
            switch category {
            case .accountSelectionMismatch: error = "Choose at least one available Mail account."
            case .missingAddresses: error = "A selected account has no configured address. Check that account in Mail."
            case .unreadableProtection: error = "Existing CLI protection records couldn't be read. Preserve them and repair or restore the file before saving."
            default: error = "Check the selected accounts, filtering instructions and political evidence terms."
            }
        } catch { self.error = error.localizedDescription }
    }

    func setFilteringEnabled(_ enabled: Bool) {
        do {
            guard let store else { throw NativeStoreError.unavailable }
            try store.setPaused(!enabled)
            loaded = try store.settings()
            paused = loaded.paused
            message = paused ? "Filtering is off. Messages remain in place." : "Filtering is on. Keep Mail-Filter enabled in Mail's Extensions settings to analyze new messages."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func analyzeSelectedMessage() {
        guard !analyzingSelectedMessage else { return }
        selectedAnalysis = nil; analyzingSelectedMessage = true
        Task { @MainActor in
            defer { analyzingSelectedMessage = false }
            var stage = "loading saved filtering settings"
            do {
                guard let store else { throw NativeStoreError.unavailable }
                let settings = try store.settings()
                stage = "reading the selected email from Mail"
                let message = try MessageDiagnostics.selectedMessage()
                stage = "classifying the selected email"
                selectedAnalysis = try await MessageDiagnostics.analyze(message, settings: settings)
            } catch is AnalysisDeadlineError {
                selectedAnalysis = "Read-only test: no messages were moved. The model did not finish within 60 seconds."
            } catch {
                selectedAnalysis = "Read-only test: no messages were moved.\nFailed while \(stage).\n\(error.localizedDescription)"
            }
        }
    }

    func copyDiagnostics() {
        guard !collectingDiagnostics else { return }
        reloadStatus()
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Mail-Filter.appex")
        let extensionBuild = extensionURL.flatMap { Bundle(url: $0) }?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let report = DiagnosticReport.summary(build: build, extensionBuild: extensionBuild, mailRunning: mailRunning,
            modelStatus: modelStatus, settings: try? store?.settings(), activity: activity)
        // Show the saved activity immediately. Log collection never blocks UI or
        // prevents the user from selecting and copying the report manually.
        diagnosticReport = report + "\nCollecting extension logs…\n"
        diagnosticMessage = "The report is shown below. Collecting extension logs (up to 10 seconds)…"
        collectingDiagnostics = true
        Task { @MainActor in
            let logs = await DiagnosticLogCollector.collect()
            diagnosticReport = report + logs.reportSection
            collectingDiagnostics = false
            copyDisplayedDiagnostics()
        }
    }

    func copyDisplayedDiagnostics() {
        guard let report = diagnosticReport else { return }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(report, forType: .string)
        diagnosticMessage = copied
            ? "Diagnostic report copied. You can also select the report below and copy it manually."
            : "Clipboard copying failed. Select the report below and press Command-C to copy it manually."
    }

    func importPrototype() {
        let panel = NSOpenPanel()
        panel.title = "Import previous Mail-Filter setup"
        panel.message = "Choose configuration.json, settings.json, or an older configured app bundle. Keep previous data until protection is imported."
        panel.allowedContentTypes = [.applicationBundle, .json]
        panel.canChooseDirectories = false
        if let oldApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mail-filter.prototype") {
            panel.directoryURL = oldApp.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        do {
            guard let store else { throw NativeStoreError.unavailable }
            let source = selected.pathExtension == "app"
                ? selected.appendingPathComponent("Contents/PlugIns/Mail-Filter Probe.appex/Contents/Resources/configuration.json") : selected
            let configuration: FilteringConfiguration
            let oldProtection: URL
            if source.lastPathComponent == "settings.json" {
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 1_024 * 1_024 else { throw NativeStoreError.invalidSettings }
                let previous = try JSONDecoder().decode(NativeSettings.self, from: Data(contentsOf: source))
                try previous.validate()
                guard let previousConfiguration = previous.configuration else { throw NativeStoreError.invalidSettings }
                configuration = previousConfiguration
                oldProtection = source.deletingLastPathComponent().appendingPathComponent("junk-protection.json")
            } else {
                configuration = try FilteringConfiguration.load(source)
                oldProtection = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/org.mail-filter.prototype.extension/Data/Library/Application Support/Mail-Filter/junk-protection.json")
            }
            let protectionFile: URL?
            do { _ = try oldProtection.resourceValues(forKeys: [.fileSizeKey]); protectionFile = oldProtection }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { protectionFile = nil }
            let settings = try store.importSetup(configuration: configuration, protectionFile: protectionFile)
            loaded = settings; applyLoadedSettings()
            message = protectionFile != nil
                ? "Previous setup and protection records imported. Enable Mail-Filter in Mail's Extensions settings and leave any earlier filtering extension disabled."
                : "Setup imported; no protection file was found at the usual location. Import Protection File in Setup & help if you previously restored messages. Keep old data until migration is verified."
            error = nil
        } catch {
            self.error = "Import failed. Keep the probe and its data. Check access to its configuration and protection file before migrating."
        }
    }

    func importProtectionFile() {
        let panel = NSOpenPanel()
        panel.title = "Import restored-message protection"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            guard let store else { throw NativeStoreError.unavailable }
            try store.importProtection(from: source)
            error = nil; message = "Protection records merged. Existing protection was preserved."
        } catch { self.error = "Protection couldn't be imported. The file must be a valid junk-protection.json from the probe or this app." }
    }

    func openMail() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app")) }
    func removeLegacyTimer() {
        do {
            try UninstallPlan.removeLegacyTimer(home: FileManager.default.homeDirectoryForCurrentUser) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["bootout", "gui/\(getuid())/org.mail-filter.agent"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit()
                guard [0, 3, 113].contains(process.terminationStatus) else { throw ToolError("The old timer couldn't be stopped. Its file was preserved.") }
            }
            legacyTimerInstalled = false; error = nil
            message = "The old timer schedule was removed. Its CLI and protection records were kept."
        } catch { self.error = error.localizedDescription }
    }
    func openUninstaller() {
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Uninstall Mail-Filter.app")
        guard FileManager.default.fileExists(atPath: sibling.path) else { error = "Open Uninstall Mail-Filter from the installer download or Applications."; return }
        NSWorkspace.shared.open(sibling)
    }
}
