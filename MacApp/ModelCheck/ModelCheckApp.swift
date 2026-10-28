import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ModelCheckDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ModelCheckApp: App {
    @NSApplicationDelegateAdaptor(ModelCheckDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            ModelCheckView()
        }.windowResizability(.contentSize)
    }
}

@MainActor
struct ModelCheckView: View {
    private struct Report: Encodable {
        let schemaVersion = 1
        let helperVersion: String
        let helperBuild: String
        let sourceRevision: String
        let sourceSHA256: String
        let sdkVersion: String
        let environment: ModelEnvironment
    }
    @State private var report = ""
    @State private var status = "Click Check This Mac to create a report."
    private let revision = Bundle.main.object(forInfoDictionaryKey: "ModelCheckSourceRevision") as? String ?? "unknown"
    private let localTest = Bundle.main.object(forInfoDictionaryKey: "ModelCheckLocalTest") as? Bool ?? true
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Mail-Filter Model Check").font(.title.bold())
            Text("Identify the on-device model selected on this Mac.")
            Text("This check does not read email, run classification or change Mail-Filter. Nothing is uploaded. The report includes hardware, macOS, model capabilities, language and power settings.")
                .font(.callout).foregroundStyle(.secondary)
            if localTest {
                Text("Local test build — distribution signing and notarization are not complete.")
                    .font(.callout).foregroundStyle(.orange)
            }
            ScrollView {
                Text(report.isEmpty ? "The report will appear here." : report)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.frame(height: 300).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Check This Mac", action: check).keyboardShortcut(.defaultAction)
                Button("Copy Report", action: copy).disabled(report.isEmpty)
                Button("Save Report…", action: save).disabled(report.isEmpty)
            }
            Text(status).font(.callout)
            Text("Version \(version) (\(build)) · macOS 27 or later · Apple silicon\nSource \(revision)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(24).frame(width: 660)
    }

    private func check() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let value = Report(helperVersion: version, helperBuild: build, sourceRevision: revision,
                sourceSHA256: Bundle.main.object(forInfoDictionaryKey: "ModelCheckSourceSHA256") as? String ?? "unknown",
                sdkVersion: Bundle.main.object(forInfoDictionaryKey: "ModelCheckSDKVersion") as? String ?? "unknown",
                environment: ModelEnvironment.capture())
            report = String(decoding: try encoder.encode(value), as: UTF8.self)
            status = "Report ready. Copy it or save a JSON file to share yourself."
        } catch { status = "Could not create the report: \(error.localizedDescription)" }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(report, forType: .string)
        status = copied ? "Report copied." : "Could not copy the report; use Save Report instead."
    }

    private func save() {
        let panel = NSSavePanel()
        panel.title = "Save model environment report"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Mail-Filter Model Environment.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(report.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            status = "Report saved. No information was uploaded."
        } catch { status = "Could not save the report: \(error.localizedDescription)" }
    }
}
