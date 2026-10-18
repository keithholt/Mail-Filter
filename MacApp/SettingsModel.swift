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
    @Published var analyzingSelectedMessage = false
    @Published var selectedAnalysis: String?
    @Published var analysisCopyMessage: String?
    @Published var exportingSelectedMessage = false
    @Published var diagnosticMessage: String?
    @Published var diagnosticReport: String?
    @Published var collectingDiagnostics = false
    @Published var manualAddresses = ""
    @Published var editingAddresses = false
    @Published var activationRequired = false
    @Published var openedEmailName: String?
    private var openedEmail: MessageDiagnostics.Selection?
    var storeDistribution: Bool { Bundle.main.object(forInfoDictionaryKey: "MailFilterDistribution") as? String == "app-store" }
    private var store: SharedStore?
    private var loaded = NativeSettings()
    private var analyzedMessageID: String?
    private var analyzedPolicyRevision: String?
    init() {
        rules = resource("filter")
        evidenceText = resource("political-evidence")
        do {
            store = try SharedStore.production()
            let wordsUpdated = try store!.updateStandardVerificationWords()
            let promptUpdated = try store!.updateStandardPrompt(rules)
            loaded = try store!.settings()
            applyLoadedSettings()
            if wordsUpdated || promptUpdated { message = "Updated the standard political policy and verification words, including Paid for by. Your accounts, filtering mode and recovery protection were preserved; custom policies remain unchanged." }
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
        activationRequired = loaded.activationRequired == true
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
            activationRequired = try store!.settings().activationRequired == true
        } catch { self.error = error.localizedDescription }
    }

    func readAccounts() {
        busy = true; error = nil
        defer { busy = false }
        do {
            let selectedAddresses = accounts.isEmpty ? Set(loaded.configuration?.selectedRecipientAddresses ?? [])
                : Set(accounts.filter { selection.contains($0.id) }.flatMap(\.addresses).map(normalizedEmailAddress))
            let protectedAddresses = Set((loaded.configuration?.ownAddresses ?? []) + accounts.flatMap(\.addresses).map(normalizedEmailAddress))
            let discovered = try AccountInventory.read()
            let missing = protectedAddresses.subtracting(discovered.flatMap(\.addresses).map(normalizedEmailAddress)).sorted()
            accounts = discovered + (missing.isEmpty ? [] : try NativeAccount.manualGroups(missing.joined(separator: "\n")))
            selection = Set(accounts.filter { !selectedAddresses.isDisjoint(with: $0.addresses.map(normalizedEmailAddress)) }.map(\.id))
            message = "Mail accounts loaded. Choose the accounts to filter, then Save Settings. Messages were not read."
        } catch {
            self.error = "Couldn't read Mail accounts. Open Mail and check Automation permission in System Settings, or use Enter Addresses to configure accounts manually."
        }
    }

    func beginManualAddresses() {
        manualAddresses = accounts.map { $0.addresses.joined(separator: ", ") }.joined(separator: "\n")
        editingAddresses = true
    }

    func useManualAddresses() {
        do {
            let previousSelected = Set(accounts.filter { selection.contains($0.id) }.flatMap(\.addresses).map(normalizedEmailAddress))
            accounts = try NativeAccount.manualGroups(manualAddresses)
            selection = Set(accounts.filter { !previousSelected.isDisjoint(with: $0.addresses) }.map(\.id))
            editingAddresses = false; error = nil
            message = "Address groups loaded. Include all your accounts and aliases, including those you leave unchecked. Choose groups to filter and save."
        } catch { self.error = "Enter one account per line, with aliases separated by commas. Use complete, unique email addresses." }
    }

    func save() {
        error = nil
        do {
            guard let store else { throw NativeStoreError.unavailable }
            let inherited = loaded.configuration?.protectedCLIIdentities ?? []
            // Select by stable IDs, so identically named accounts remain distinct.
            let inventory = accounts.map { FilteringAccount(id: $0.id, name: $0.id, addresses: $0.addresses) }
            let made = try FilteringConfiguration.make(selectedNames: selection.sorted(), inventory: inventory, rules: rules,
                evidenceTerms: politicalEvidenceTerms(evidenceText), mode: preview ? "dry-run" : "apply", protectedCLIIdentities: inherited)
            let current = try store.settings()
            let configuration = FilteringConfiguration(schemaVersion: 2, mode: made.mode, selectedRecipientAddresses: made.selectedRecipientAddresses,
                ownAddresses: made.ownAddresses, rules: made.rules, evidenceTerms: made.evidenceTerms,
                legacyAccountIDs: Array(Set(made.legacyAccountIDs + (current.configuration?.legacyAccountIDs ?? []))).sorted(),
                protectedCLIIdentities: Array(Set(made.protectedCLIIdentities + (current.configuration?.protectedCLIIdentities ?? []))).sorted())
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
        openedEmail = nil; openedEmailName = nil
        analyzeMessage(nil)
    }

    func analyzeEmailFile() {
        let panel = NSOpenPanel()
        panel.title = "Open email source for read-only analysis"
        panel.allowedContentTypes = [UTType(filenameExtension: "eml") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let selection = try withFileAccess(url) { try MessageDiagnostics.emailFile(url) }
            openedEmail = selection; openedEmailName = url.lastPathComponent
            analyzeMessage(selection)
        } catch { selectedAnalysis = "Couldn't read this email file: \(error.localizedDescription)" }
    }

    private func analyzeMessage(_ supplied: MessageDiagnostics.Selection?) {
        guard !analyzingSelectedMessage else { return }
        selectedAnalysis = nil; analyzedMessageID = nil; analysisCopyMessage = nil; analyzingSelectedMessage = true
        Task { @MainActor in
            defer { analyzingSelectedMessage = false }
            var stage = "loading saved filtering settings"
            do {
                guard let store else { throw NativeStoreError.unavailable }
                let settings = try store.settings()
                stage = "reading the selected email from Mail"
                let message = try supplied ?? MessageDiagnostics.selectedMessage()
                stage = "classifying the selected email"
                selectedAnalysis = try await MessageDiagnostics.analyze(message, settings: settings, activity: store.activity())
                analyzedMessageID = message.message.messageID
                analyzedPolicyRevision = settings.revision
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
        diagnosticReport = report
        diagnosticMessage = "Collecting private processing history…"
        collectingDiagnostics = true
        let directory = store?.directory
        Task { @MainActor in
            let events = await Task.detached(priority: .utility) { () -> [NativeActivity]? in
                directory.flatMap { try? SharedStore(directory: $0).diagnosticEvents() }
            }.value
            let formatter = ISO8601DateFormatter()
            let records = (events ?? []).suffix(200).map { event in
                var line = "\(formatter.string(from: event.date)) \(event.outcome) \(event.category) key=\(event.traceID ?? "unavailable") attempt=\(event.attempt ?? 0)"
                if let build = event.build { line += " build=\(build)" }
                if let channel = event.channel { line += " channel=\(channel)" }
                if let domain = event.failureDomain, let code = event.failureCode { line += " error=\(domain):\(code)" }
                return line
            }.joined(separator: "\n")
            let emptyHistory = events == nil ? "Private file history unavailable; saved activity above is still usable.\n" : "No additional records available.\n"
            diagnosticReport = report + "\nPrivate processing history (up to 7 days):\n" + (records.isEmpty ? emptyHistory : records + "\n")
            #if !APP_STORE
            if !storeDistribution {
                let logs = await DiagnosticLogCollector.collect()
                diagnosticReport = (diagnosticReport ?? report) + logs.reportSection
            }
            #endif
            collectingDiagnostics = false
            copyDisplayedDiagnostics()
        }
    }

    func copySelectedAnalysis() {
        guard let selectedAnalysis else { return }
        NSPasteboard.general.clearContents()
        analysisCopyMessage = NSPasteboard.general.setString(selectedAnalysis, forType: .string)
            ? "Analysis result copied. It may contain quotes from the selected email."
            : "Couldn't copy the analysis result. Select its text and copy manually."
    }

    func exportSelectedEmailReport() {
        exportEmailReport(openedFile: false)
    }

    func exportOpenedEmailReport() { exportEmailReport(openedFile: true) }

    private func exportEmailReport(openedFile: Bool) {
        guard !exportingSelectedMessage && !analyzingSelectedMessage else { return }
        exportingSelectedMessage = true
        Task { @MainActor in
            defer { exportingSelectedMessage = false }
            do {
                guard let store else { throw NativeStoreError.unavailable }
                let selection: MessageDiagnostics.Selection
                if openedFile, let openedEmail { selection = openedEmail }
                else { selection = try MessageDiagnostics.selectedMessage() }
                let settings = try store.settings()
                let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Mail-Filter.appex")
                let report = SelectedEmailReport(selection: selection, settings: settings, activity: try store.activity(),
                    analysis: analyzedMessageID == selection.message.messageID && analyzedPolicyRevision == settings.revision ? selectedAnalysis : nil,
                    appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    extensionBuild: extensionURL.flatMap { Bundle(url: $0) }?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                let panel = NSSavePanel()
                panel.title = "Export selected email report"
                panel.message = "This file contains the selected email's full source, extracted text, current filtering rules and processing history. Share it only with someone you want to inspect this email. No messages will be moved."
                panel.nameFieldStringValue = "Mail-Filter Diagnostic \(report.diagnosticKey ?? "selected-email").json"
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true
                let response = await withCheckedContinuation { continuation in
                    panel.begin { continuation.resume(returning: $0) }
                }
                guard response == .OK, let url = panel.url else { return }
                try withFileAccess(url) { try report.write(to: url) }
                analysisCopyMessage = "Email report exported to \(url.lastPathComponent). Attach that file when reporting this email."
            } catch { analysisCopyMessage = "Couldn't export the selected email: \(error.localizedDescription)" }
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
        panel.message = "Choose a Mail-Filter setup export, or a previous data folder containing settings.json and junk-protection.json. The import preserves preferences and waits for your confirmation before filtering."
        panel.allowedContentTypes = [.json, .folder]
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        do {
            guard let store else { throw NativeStoreError.unavailable }
            let archive = try withFileAccess(selected) {
                if try selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    // Directory selection authorizes both siblings. Never silently
                    // omit protection because the sandbox can't see it.
                    return try SetupArchive.readLegacyFolder(selected)
                }
                return try SetupArchive.read(from: selected)
            }
            let settings = try store.importSetup(archive)
            loaded = settings; applyLoadedSettings()
            message = "Setup and protection imported. Review the preferences, then Confirm Imported Setup. The previous destination setup was backed up privately."
            error = nil
        } catch {
            self.error = "Import failed. Choose a complete setup export or a data folder with settings and protection. Your active setup was preserved."
        }
    }

    func confirmImportedSetup() {
        do {
            try store?.confirmImportedSetup()
            loaded = try store!.settings(); applyLoadedSettings()
            message = paused ? "Imported setup confirmed. Filtering remains off as previously configured." : "Imported setup confirmed. Filtering can resume when the Mail extension is enabled."
        } catch { self.error = error.localizedDescription }
    }

    func exportSetup() {
        do {
            guard let store else { throw NativeStoreError.unavailable }
            let archive = try store.exportSetup()
            let panel = NSSavePanel()
            panel.title = "Export setup and restored-message protection"
            panel.message = "This private file includes your account addresses, filtering instructions and recovery records. Keep it secure."
            panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Mail-Filter Setup.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try withFileAccess(url) { try archive.write(to: url) }
            message = "Setup and recovery protection exported."
        } catch { self.error = error.localizedDescription }
    }

    func exportDiagnostics() {
        guard let diagnosticReport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Mail-Filter Support.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try withFileAccess(url) {
                try diagnosticReport.write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func withFileAccess<T>(_ url: URL, operation: () throws -> T) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    func importProtectionFile() {
        let panel = NSOpenPanel()
        panel.title = "Import restored-message protection"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            guard let store else { throw NativeStoreError.unavailable }
            try withFileAccess(source) { try store.importProtection(from: source) }
            error = nil; message = "Protection records merged. Existing protection was preserved."
        } catch { self.error = "Protection couldn't be imported. Choose a valid junk-protection.json file from an earlier installation." }
    }

    func openMail() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app")) }
    func openUninstaller() {
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Uninstall Mail-Filter.app")
        guard FileManager.default.fileExists(atPath: sibling.path) else { error = "Open Uninstall Mail-Filter from the installer download or Applications."; return }
        NSWorkspace.shared.open(sibling)
    }
}
