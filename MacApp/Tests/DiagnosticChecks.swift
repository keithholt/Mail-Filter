import Foundation

struct DiagnosticCheckFailure: Error { let name: String }

@main
@MainActor
struct DiagnosticChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw DiagnosticCheckFailure(name: name) }
        count += 1
    }

    static func main() async throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        let normal = await DiagnosticLogCollector.run(executable: shell, arguments: ["-c", "printf 'callback received\\n'"])
        try check(normal.status == .collected && normal.text == "callback received\n", "normal output is collected")

        let large = await DiagnosticLogCollector.run(executable: shell,
            arguments: ["-c", "i=0; while [ \"$i\" -lt 2000 ]; do printf '0123456789012345678901234567890123456789'; i=$((i+1)); done; printf 'final-marker'"],
            timeout: 3, maximumBytes: 128)
        try check(large.status == .collected && large.text.utf8.count == 128 && large.text.hasSuffix("final-marker"),
                  "output larger than pipe capacity is drained while retaining only its bounded tail")

        let began = ProcessInfo.processInfo.systemUptime
        let stalled = await DiagnosticLogCollector.run(executable: shell,
            arguments: ["-c", "trap '' TERM; printf 'begun'; while :; do :; done"], timeout: 0.2)
        try check(stalled.status == .timedOut && ProcessInfo.processInfo.systemUptime - began < 2,
                  "a process ignoring termination cannot hang report generation")
        try check(stalled.text == "begun", "a timeout keeps the available partial log")

        let inheritedPipeStart = ProcessInfo.processInfo.systemUptime
        let inheritedPipe = await DiagnosticLogCollector.run(executable: shell,
            arguments: ["-c", "sleep 1 & printf 'parent finished'"], timeout: 2)
        try check(inheritedPipe.status == .collected && inheritedPipe.text == "parent finished"
                  && ProcessInfo.processInfo.systemUptime - inheritedPipeStart < 0.8,
                  "a descendant retaining stdout does not force an EOF wait")

        let rejected = await DiagnosticLogCollector.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        try check(rejected.status == .unavailable && rejected.reportSection.contains("activity above is still usable"),
                  "a denied log command still permits an activity report")
        let missing = await DiagnosticLogCollector.run(executable: URL(fileURLWithPath: "/nonexistent-mail-filter-test-command"), arguments: [])
        try check(missing.status == .unavailable, "launch failure returns a usable unavailable status")

        var heartbeatRan = false
        let heartbeat = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            heartbeatRan = true
        }
        _ = await DiagnosticLogCollector.run(executable: shell, arguments: ["-c", "sleep 0.15"])
        try check(heartbeatRan, "the main actor remains responsive while logs are collected")
        await heartbeat.value

        var settings = NativeSettings()
        settings.inventory = [NativeAccount(id: "private-id-marker", name: "private-name-marker", addresses: ["private-address@example.org"])]
        settings.selectedAccountIDs = ["private-id-marker"]
        let oldReport = DiagnosticReport.summary(build: "8", extensionBuild: "8", mailRunning: true,
            modelStatus: "Ready", settings: settings, activity: NativeActivityLog())
        try check(oldReport.contains("not recorded by earlier builds"),
                  "missing legacy callback counters are not represented as measured zero")
        try check(oldReport.contains("Last recorded extension start: unavailable"), "legacy diagnostics do not confuse installed metadata with running identity")
        try check(!oldReport.contains("private-id-marker") && !oldReport.contains("private-name-marker")
                  && !oldReport.contains("private-address@example.org") && oldReport.contains("Selected accounts: 1"),
                  "report includes account count without publishing private account details")
        var activity = NativeActivityLog()
        activity.receivedCallbacks = 2
        activity.lastCallback = Date()
        activity.recent = [NativeActivity(outcome: "analysisStarted", category: "onDeviceModel", traceID: "012345abcdef")]
        let report = DiagnosticReport.summary(build: "8", extensionBuild: "8", mailRunning: true,
            modelStatus: "Ready", settings: settings, activity: activity)
        try check(report.contains("Received callbacks: 2") && report.contains("key=012345abcdef"),
                  "activity stages and the diagnostic key remain shareable")
        activity.lastExtensionStart = NativeActivity(outcome: "extensionStarted", category: "pid-123", build: "20", channel: "direct")
        let mismatch = DiagnosticReport.summary(build: "21", extensionBuild: "21", mailRunning: true,
            modelStatus: "Ready", settings: settings, activity: activity)
        try check(mismatch.contains("Installed extension build: 21") && mismatch.contains("Last recorded extension start: build 20; pid-123")
                  && mismatch.contains("differs from this app's build"), "a replaced on-disk extension does not conceal the previous startup build")
        try check(mismatch.contains("not a check that the process is still running"), "historical startup identity is not presented as a live process test")
        let now = Date()
        let waiting = NativeActivity(date: now.addingTimeInterval(-60), outcome: "callbackReceived", category: "bodyRequested", traceID: "012345abcdef")
        let ready = NativeActivity(date: now.addingTimeInterval(-10), outcome: "callbackReceived", category: "bodyReady", traceID: "012345abcdef", bodyWaitMilliseconds: 50000)
        try check(DiagnosticReport.pendingBodies([waiting], now: now).contains("waitingSeconds=60"), "retained history identifies a pending body without a background timer")
        try check(DiagnosticReport.pendingBodies([ready, waiting], now: now).isEmpty, "a matching newer body callback resolves the pending diagnostic")
        let failedBody = NativeActivity(date: now.addingTimeInterval(-5), outcome: "review", category: "bodyUnavailable", traceID: "012345abcdef")
        try check(DiagnosticReport.pendingBodies([waiting, failedBody], now: now).isEmpty, "terminal body failure resolves pending state even if events are unsorted")
        try check(DiagnosticReport.pendingBodies([waiting], now: now.addingTimeInterval(-40)).isEmpty, "recent requests are not described as stalled")
        activity.recent = [ready]
        let measured = DiagnosticReport.summary(build: "24", extensionBuild: "24", mailRunning: true, modelStatus: "Ready", settings: settings, activity: activity)
        try check(measured.contains("bodyWaitMs=50000") && measured.contains("Physical memory:") && measured.contains("macOS:"), "support reports show body latency and system context")
        print("Passed \(count) diagnostic collection, timeout, responsiveness and privacy checks; no Mail or clipboard actions")
    }
}
