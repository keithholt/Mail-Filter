import Foundation
import Darwin

enum DiagnosticReport {
    static func summary(build: String, extensionBuild: String?, mailRunning: Bool, modelStatus: String,
                        settings: NativeSettings?, activity: NativeActivityLog) -> String {
        let formatter = ISO8601DateFormatter()
        var report = "Mail-Filter diagnostic report\nBuild: \(build)\nInstalled extension build: \(extensionBuild ?? "unknown")\nMail running: \(mailRunning)\nModel: \(modelStatus)\n"
        if let settings {
            report += "Filtering paused: \(settings.paused)\nMode: \(settings.configuration?.mode ?? "setup required")\nSelected accounts: \(settings.selectedAccountIDs.count)\n"
        } else { report += "Saved filtering settings: unavailable\n" }
        report += "Received callbacks: \(activity.receivedCallbacks.map(String.init) ?? "not recorded by earlier builds")\nLast callback: \(activity.lastCallback.map(formatter.string) ?? "not recorded")\nClassified: \(activity.processed)\nJunk actions requested: \(activity.junkRequested)\n"
        for event in activity.recent.prefix(30) {
            report += "\(formatter.string(from: event.date)) \(event.outcome) \(event.category) key=\(event.traceID ?? "unavailable")"
            if let attempt = event.attempt { report += " attempt=\(attempt)" }
            if let domain = event.failureDomain, let code = event.failureCode { report += " error=\(domain):\(code)" }
            report += "\n"
        }
        return report
    }
}

struct DiagnosticLogResult: Sendable {
    enum Status: Sendable { case collected, timedOut, unavailable }
    let status: Status
    let text: String

    var reportSection: String {
        let heading: String
        switch status {
        case .collected: heading = text.isEmpty ? "No matching extension logs were found." : "Extension logs (last 6 hours):"
        case .timedOut: heading = "Extension log collection timed out; available output follows."
        case .unavailable: heading = "Extension logs were unavailable; activity above is still usable."
        }
        return "\n" + heading + (text.isEmpty ? "\n" : "\n" + text + "\n")
    }
}

enum DiagnosticLogCollector {
    static func collect() async -> DiagnosticLogResult {
        // Only this app's fixed-category logs; never collect Mail's email logs.
        await run(executable: URL(fileURLWithPath: "/usr/bin/log"), arguments: [
            "show", "--last", "6h", "--style", "compact", "--info", "--predicate",
            "subsystem == \"org.mail-filter.app\""
        ])
    }

    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 10,
                    maximumBytes: Int = 32_000) async -> DiagnosticLogResult {
        await Task.detached(priority: .utility) {
            runInBackground(executable: executable, arguments: arguments,
                            timeout: timeout, maximumBytes: maximumBytes)
        }.value
    }

    private static func runInBackground(executable: URL, arguments: [String], timeout: TimeInterval,
                                        maximumBytes: Int) -> DiagnosticLogResult {
        let process = Process(), output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let descriptor = output.fileHandleForReading.fileDescriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            return DiagnosticLogResult(status: .unavailable, text: "")
        }
        defer { try? output.fileHandleForReading.close() }
        do { try process.run() }
        catch { return DiagnosticLogResult(status: .unavailable, text: "") }
        // A nonblocking pipe avoids waiting forever for EOF, including when a
        // descendant retains stdout. Only the bounded tail is kept in memory.
        try? output.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        let limit = max(0, maximumBytes)
        var tail = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                return DiagnosticLogResult(status: .timedOut, text: String(decoding: tail, as: UTF8.self))
            }
            let amount = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if amount > 0 {
                tail.append(contentsOf: buffer.prefix(amount))
                if tail.count > limit { tail.removeFirst(tail.count - limit) }
                continue
            }
            if !process.isRunning {
                let status: DiagnosticLogResult.Status = process.terminationStatus == 0 ? .collected : .unavailable
                return DiagnosticLogResult(status: status, text: String(decoding: tail, as: UTF8.self))
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
