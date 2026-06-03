import Foundation

final class MeetWatcher {
    // Persisted toggle — the only user-facing control.
    static var isRecordingEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "recordingDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "recordingDisabled") }
    }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.local.meetrecorder.watcher", qos: .utility)
    private let axClient = AXMeetClient()

    private(set) var chromeDetected = false
    private(set) var meetDetected = false
    private(set) var accessibilityTrusted = false
    private(set) var lastRecordingTime: Date?

    private var lastSeenSessionKeys = Set<String>()

    func start() {
        onRecordingStarted = { [weak self] _ in
            self?.lastRecordingTime = Date()
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 3.0)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
        Logger.log("MeetWatcher started. Auto-record: \(MeetWatcher.isRecordingEnabled ? "on" : "off").")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        accessibilityTrusted = AXMeetClient.isAccessibilityTrusted(prompt: false)
        chromeDetected = !AXMeetClient.runningChromeApps().isEmpty

        guard accessibilityTrusted else {
            meetDetected = false
            lastSeenSessionKeys.removeAll()
            return
        }

        let sessions = axClient.findMeetSessions()
        meetDetected = !sessions.isEmpty
        let sessionKeys = Set(sessions.map(\.key))

        let closed = lastSeenSessionKeys.subtracting(sessionKeys)
        for key in closed { clearSession(key: key) }
        lastSeenSessionKeys = sessionKeys

        guard MeetWatcher.isRecordingEnabled else { return }

        for session in sessions {
            attemptStartRecording(session: session, client: axClient)
        }
    }
}
