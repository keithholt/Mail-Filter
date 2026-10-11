import SwiftUI
import AppKit
import Darwin

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var eraseData = false
    @Published var removeTimer = false
    @Published var busy = false
    @Published var result: String?
    @Published var completed = false

    func uninstall() async {
        busy = true; result = nil
        defer { busy = false }
        do {
            let store = try SharedStore.production()
            var targets = try UninstallPlan.applicationsToRemove()
            if let commandLinePath = try UninstallPlan.commandLinePathToRemove() { targets.append(commandLinePath) }
            // A corrupt settings file already blocks actions; otherwise pause it.
            do { try store.setPaused(true) }
            catch NativeStoreError.invalidSettings { }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: UninstallPlan.appIdentifier) { app.terminate() }
            if !targets.isEmpty {
                // Native Finder-style removal; AppKit presents any necessary UI.
                let recycled: [URL: URL] = try await withCheckedThrowingContinuation { continuation in
                    NSWorkspace.shared.recycle(targets) { locations, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: locations) }
                    }
                }
                guard targets.allSatisfy({ recycled[$0] != nil }) else { throw UninstallError.unexpectedApplication }
            }
            if removeTimer {
                try UninstallPlan.removeLegacyTimer(home: FileManager.default.homeDirectoryForCurrentUser) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    process.arguments = ["bootout", "gui/\(getuid())/org.mail-filter.agent"]
                    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                    try process.run(); process.waitUntilExit()
                    // A missing service is normal; remove only the verified plist.
                    guard process.terminationStatus == 0 || process.terminationStatus == 3 || process.terminationStatus == 113 else {
                        throw ToolError("The timer could not be stopped; its installation file was preserved.")
                    }
                }
            }
            if eraseData { try store.eraseApplicationData() }
            completed = true
            result = "Mail-Filter moved to Trash. Its installer-managed command-line access was removed; open a new Terminal window to refresh PATH. \(eraseData ? "Its private settings, activity and protection records were erased." : "Private settings and restored-message protection were kept for reinstalling.") Your messages and Mail accounts were not changed. Restart Mail if the extension remains listed."
        } catch {
            result = "Removal did not fully complete. \(error.localizedDescription) Filtering was paused where possible. Check Applications before retrying; you can also move the installed apps to Trash in Finder."
        }
    }
}

@main
struct MailFilterUninstaller: App {
    @StateObject private var model = UninstallerModel()
    var body: some Scene {
        WindowGroup("Uninstall Mail-Filter") {
            VStack(alignment: .leading, spacing: 18) {
                Label("Uninstall Mail-Filter", systemImage: "envelope").font(.title2.bold())
                Text("Remove Mail-Filter and its Mail extension from Applications. No email messages or Mail accounts will be changed.")
                Toggle("Erase private settings, activity and restored-message protection", isOn: $model.eraseData)
                Text("Leave this unchecked to preserve protection if you reinstall.").font(.caption).foregroundStyle(.secondary)
                Toggle("Also remove the old timer agent installation", isOn: $model.removeTimer)
                Text("Installer-managed command-line access is removed too. The previous probe, your development checkout, its launcher and their private data are kept.").font(.caption).foregroundStyle(.secondary)
                if let result = model.result { Text(result).font(.callout).textSelection(.enabled) }
                HStack {
                    Button(model.completed ? "Close" : "Cancel") { NSApplication.shared.terminate(nil) }.disabled(model.busy)
                    Spacer()
                    if !model.completed { Button("Remove Mail-Filter") { Task { await model.uninstall() } }.buttonStyle(.borderedProminent).disabled(model.busy) }
                }
            }.padding(26).frame(width: 570)
        }.windowResizability(.contentSize)
    }
}
