import SwiftUI
import AppKit

final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MailFilterApp: App {
    @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) private var delegate
    @StateObject private var model = SettingsModel()

    var body: some Scene {
        WindowGroup("Mail-Filter") { SettingsView(model: model) }.defaultSize(width: 900, height: 750)
            .commands {
                CommandGroup(after: .appInfo) {
                    if !model.storeDistribution { Button("Uninstall Mail-Filter…", action: model.openUninstaller) }
                }
            }
    }
}
