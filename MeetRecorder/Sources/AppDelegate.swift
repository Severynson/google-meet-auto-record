import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusBar: StatusBarController?
    private(set) var watcher: MeetWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent duplicate instances — signal the running one to show its window.
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != currentPID }

        if !others.isEmpty {
            DistributedNotificationCenter.default().post(
                name: .meetRecorderShowWindow, object: nil
            )
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

        let isDaemon = CommandLine.arguments.contains("--daemon")

        if !isDaemon {
            // Silently install or repair login item on first launch.
            // Repair removes old KeepAlive plists and stale executable paths.
            try? LaunchAgentManager.installOrRepair()
            showWindow()
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
}

extension Notification.Name {
    static let meetRecorderShowWindow = Notification.Name("com.local.meetrecorder.showWindow")
}
