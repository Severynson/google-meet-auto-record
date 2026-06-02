import Foundation

struct ShellResult {
    let exitCode: Int32
    let output: String
}

@discardableResult
func shell(_ cmd: String) -> ShellResult {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", cmd]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.launch()
    task.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ShellResult(exitCode: task.terminationStatus, output: out)
}

enum LaunchAgentState {
    case notInstalled
    case installedRunning
    case installedStopped
}

struct LaunchAgentManager {
    static let label = "com.local.meetrecorder"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func state() -> LaunchAgentState {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return .notInstalled
        }
        let r = shell("launchctl list \(label) 2>/dev/null")
        return r.exitCode == 0 ? .installedRunning : .installedStopped
    }

    // Install plist and load (start) the service.
    static func install() throws {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plistContents().write(to: plistURL, atomically: true, encoding: .utf8)
        let r = shell("launchctl load '\(plistURL.path)'")
        if r.exitCode != 0 {
            throw makeError("launchctl load failed: \(r.output)")
        }
        Logger.log("LaunchAgent installed and started.")
    }

    // Unload + delete plist.
    static func uninstall() {
        shell("launchctl unload '\(plistURL.path)' 2>/dev/null")
        try? FileManager.default.removeItem(at: plistURL)
        Logger.log("LaunchAgent uninstalled.")
    }

    // Load existing plist (re-enable after disable).
    static func enable() throws {
        let r = shell("launchctl load '\(plistURL.path)'")
        if r.exitCode != 0 {
            throw makeError("launchctl load failed: \(r.output)")
        }
        Logger.log("LaunchAgent enabled.")
    }

    // Unload without deleting plist (keeps auto-start configured but stops service).
    static func disable() {
        shell("launchctl unload '\(plistURL.path)' 2>/dev/null")
        Logger.log("LaunchAgent disabled.")
    }

    private static func plistContents() -> String {
        let exec = Bundle.main.executablePath ?? "/Applications/MeetRecorder.app/Contents/MacOS/MeetRecorder"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(exec)</string>
                <string>--daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private static func makeError(_ msg: String) -> Error {
        NSError(domain: "LaunchAgentManager", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
