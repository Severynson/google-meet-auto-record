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
            // Silently install login item on first launch if not already set up.
            if LaunchAgentManager.state() == .notInstalled {
                try? LaunchAgentManager.install()
            }
            showWindow()
        }
    }

    @objc func showWindow() {
        statusBar?.showStatusWindow()
    }
}

extension Notification.Name {
    static let meetRecorderShowWindow = Notification.Name("com.local.meetrecorder.showWindow")
}
