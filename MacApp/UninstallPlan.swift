import Foundation

enum UninstallError: LocalizedError {
    case unexpectedApplication, unexpectedAgent, unexpectedCommandLinePath
    var errorDescription: String? {
        switch self {
        case .unexpectedApplication: return "The installed app does not match Mail-Filter. Nothing was removed."
        case .unexpectedAgent: return "The old timer file is not a recognized Mail-Filter agent. It was left unchanged."
        case .unexpectedCommandLinePath: return "The command-line PATH entry does not match Mail-Filter. It was left unchanged."
        }
    }
}

enum UninstallPlan {
    static let appIdentifier = "org.mail-filter.app"
    static let uninstallerIdentifier = "org.mail-filter.uninstaller"
    static let commandLineDirectory = "/Applications/Mail-Filter.app/Contents/Resources/DeveloperTools/bin"

    static func commandLinePathToRemove(etc: URL = URL(fileURLWithPath: "/etc")) throws -> URL? {
        let path = etc.appendingPathComponent("paths.d/org.mail-filter.command-line")
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: path.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 4096,
              try Data(contentsOf: path) == Data((commandLineDirectory + "\n").utf8) else {
            throw UninstallError.unexpectedCommandLinePath
        }
        return path
    }

    /// Validate the complete, fixed product list before asking macOS to move it
    /// to Trash. Configuration and arbitrary user paths never enter this list.
    static func applicationsToRemove(applications: URL = URL(fileURLWithPath: "/Applications")) throws -> [URL] {
        let products = [("Mail-Filter.app", appIdentifier), ("Uninstall Mail-Filter.app", uninstallerIdentifier)]
        var targets: [URL] = []
        for (name, identifier) in products {
            let url = applications.appendingPathComponent(name)
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { continue }
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw UninstallError.unexpectedApplication }
            let info = url.appendingPathComponent("Contents/Info.plist")
            let size = try info.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 1_024 * 1_024,
                  let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any],
                  plist["CFBundleIdentifier"] as? String == identifier else { throw UninstallError.unexpectedApplication }
            targets.append(url)
        }
        return targets
    }

    static func removeLegacyTimer(home: URL, unload: () throws -> Void) throws {
        let path = home.appendingPathComponent("Library/LaunchAgents/org.mail-filter.agent.plist")
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        let data = try Data(contentsOf: path)
        guard data.count <= 64 * 1_024,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == "org.mail-filter.agent",
              let args = plist["ProgramArguments"] as? [String], let executable = args.first,
              URL(fileURLWithPath: executable).lastPathComponent == "mail-filter" else { throw UninstallError.unexpectedAgent }
        try unload()
        try FileManager.default.removeItem(at: path)
    }
}
