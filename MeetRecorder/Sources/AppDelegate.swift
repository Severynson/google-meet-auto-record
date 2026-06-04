import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let daemonLaunchTimestampKey = "lastDaemonLaunchTimestamp"
    private static let loginSuppressWindowSeconds: TimeInterval = 120

    private(set) var statusBar: StatusBarController?
    private(set) var watcher: MeetWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDaemon = CommandLine.arguments.contains("--daemon")
        if isDaemon {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.daemonLaunchTimestampKey)
        }

        // Prevent duplicate instances — signal the running one to show its window.
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != currentPID }

        if !others.isEmpty {
            if isDaemon || Self.recentDaemonLaunch() {
                Logger.log("Duplicate launch suppressed window: daemon=\(isDaemon).")
            } else {
                DistributedNotificationCenter.default().post(
                    name: .meetRecorderShowWindow, object: nil
                )
            }
            NSApp.terminate(nil)
            return
        }

        watcher = MeetWatcher()
        watcher?.start()

        statusBar = StatusBarController()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showWindow),
            name: .meetRecorderShowWindow,
            object: nil
        )

        if !isDaemon {
            let agentWasInstalled = LaunchAgentManager.state() != .notInstalled
            // Silently install or repair login item on first launch.
            // Repair removes old KeepAlive plists and stale executable paths.
            try? LaunchAgentManager.installOrRepair()
            if agentWasInstalled && Self.isNearLoginTime() {
                Logger.log("Startup launch kept hidden; window can be opened from status item.")
            } else {
                showWindow()
            }
        }
    }

    @objc func showWindow() {
        statusBar?.showStatusWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    func reopenApp() {
        let bundleURL = Bundle.main.bundleURL
        LaunchAgentManager.relaunchThroughLaunchAgent(showBundleURL: bundleURL)
        NSApp.terminate(nil)
    }

    private static func recentDaemonLaunch() -> Bool {
        let timestamp = UserDefaults.standard.double(forKey: daemonLaunchTimestampKey)
        guard timestamp > 0 else { return false }
        return Date().timeIntervalSince1970 - timestamp < loginSuppressWindowSeconds
    }

    private static func isNearLoginTime() -> Bool {
        ProcessInfo.processInfo.systemUptime < loginSuppressWindowSeconds
    }
}

extension Notification.Name {
    static let meetRecorderShowWindow = Notification.Name("com.local.meetrecorder.showWindow")
}
