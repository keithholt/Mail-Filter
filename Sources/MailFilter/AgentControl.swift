import Foundation
import Darwin

enum AgentRunAction: Equatable { case alreadyRunning, kickstart, bootstrap }

func agentRunAction(loaded: Bool, running: Bool, installed: Bool) throws -> AgentRunAction {
    if loaded { return running ? .alreadyRunning : .kickstart }
    guard installed else { throw ToolError("Agent is not installed. Run ./scripts/agent.sh install for dry-run scheduling or install-apply to enable moves.") }
    return .bootstrap
}

func triggerAgentRun() throws {
    let target = "gui/\(getuid())/org.mail-filter.agent"
    let domain = "gui/\(getuid())"
    let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/org.mail-filter.agent.plist").path
    func launchctl(_ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    let (status, output) = try launchctl(["print", target])
    let running = output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "state = running" }
    let action = try agentRunAction(loaded: status == 0, running: running, installed: FileManager.default.fileExists(atPath: plist))
    if action == .alreadyRunning {
        print("Mail-Filter is already running; no additional batch started.")
        return
    }
    let arguments = action == .bootstrap ? ["bootstrap", domain, plist] : ["kickstart", target]
    let (result, error) = try launchctl(arguments)
    guard result == 0 else { throw ToolError("Could not trigger Mail-Filter: \(error.trimmingCharacters(in: .whitespacesAndNewlines))") }
    print("Immediate background run requested in the agent's saved mode. Check ./scripts/agent.sh logs for results.")
}
