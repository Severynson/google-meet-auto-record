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

    static var currentExecutablePath: String {
        Bundle.main.executablePath ?? "/Applications/MeetRecorder.app/Contents/MacOS/MeetRecorder"
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
        try writeCurrentPlist()
        let r = shell("launchctl load '\(plistURL.path)'")
        if r.exitCode != 0 {
            throw makeError("launchctl load failed: \(r.output)")
        }
        Logger.log("LaunchAgent installed and started.")
    }

    static func installOrRepair() throws {
        let currentState = state()
        let repairNeeded = currentState == .notInstalled || plistNeedsRepair()

        guard repairNeeded else { return }

        if currentState == .installedRunning {
            shell("launchctl unload '\(plistURL.path)' 2>/dev/null")
        }

        try writeCurrentPlist()

        let r = shell("launchctl load '\(plistURL.path)'")
        if r.exitCode != 0 {
            throw makeError("launchctl load failed: \(r.output)")
        }
        Logger.log("LaunchAgent installed/repaired and started.")
    }

    static func relaunchThroughLaunchAgent(showBundleURL bundleURL: URL) {
        shell("launchctl unload '\(plistURL.path)' 2>/dev/null")
        try? writeCurrentPlist()

        let script = """
        sleep 0.5
        launchctl load '\(plistURL.path)'
        sleep 0.5
        /usr/bin/open '\(bundleURL.path)'
        """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]

        do {
            try task.run()
            Logger.log("LaunchAgent relaunch scheduled.")
        } catch {
            Logger.log("Failed to schedule LaunchAgent relaunch: \(error)")
        }
    }

    private static func writeCurrentPlist() throws {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plistContents().write(to: plistURL, atomically: true, encoding: .utf8)
    }

    // Unload + delete plist.
    static func uninstall() {
        shell("launchctl unload '\(plistURL.path)' 2>/dev/null")
        try? FileManager.default.removeItem(at: plistURL)
        Logger.log("LaunchAgent uninstalled.")
    }

    // Load existing plist (re-enable after disable).
    static func enable() throws {
        if plistNeedsRepair() {
            try writeCurrentPlist()
        }
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

    // Full uninstall. The app cannot delete its own bundle while running, so we
    // spawn a DETACHED bash helper (binary is /bin/bash, outside the bundle) that
    // outlives this process: it sleeps until the app has quit, then unloads the
    // daemon, kills both running instances (GUI + --daemon, same process name),
    // removes the accessibility grant, the plist, and finally the app bundle.
    //
    // pkill uses -x (exact process NAME) not -f (full command line): the helper's
    // own command line contains the string "MeetRecorder" (the rm paths), so -f
    // would match and kill the helper mid-uninstall. -x matches only the real
    // "MeetRecorder" binary — never this bash helper.
    static func performSelfUninstall() {
        let plistPath = plistURL.path
        let script = """
        sleep 1
        launchctl unload '\(plistPath)' 2>/dev/null
        pkill -x MeetRecorder 2>/dev/null
        tccutil reset Accessibility \(label) 2>/dev/null
        rm -f '\(plistPath)'
        rm -rf /Applications/MeetRecorder.app
        """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]

        do {
            try task.run()
            Logger.log("Self-uninstall helper launched.")
        } catch {
            Logger.log("Failed to launch self-uninstall helper: \(error)")
        }
    }

    private static func plistContents() -> String {
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
                <string>\(currentExecutablePath)</string>
                <string>--daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private static func plistNeedsRepair() -> Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return true
        }

        let args = plist["ProgramArguments"] as? [String]
        let installedExecutable = args?.first
        let keepAliveExists = plist["KeepAlive"] != nil

        return installedExecutable != currentExecutablePath || keepAliveExists
    }

    private static func makeError(_ msg: String) -> Error {
        NSError(domain: "LaunchAgentManager", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
