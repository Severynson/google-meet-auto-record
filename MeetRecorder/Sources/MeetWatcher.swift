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

    private(set) var browserDetected = false
    private(set) var meetDetected = false
    private(set) var inCallDetected = false
    private(set) var accessibilityTrusted = false
    private(set) var lastRecordingTime: Date?
    private(set) var lastAutomationStatus: String?

    func start() {
        onRecordingStarted = { [weak self] _ in
            self?.lastRecordingTime = Date()
        }
        onAutomationStatus = { [weak self] message in
            self?.lastAutomationStatus = message
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Poll every second: lobby and live call share the same URL, so we must
        // keep checking for the "more options" control to know when to start.
        t.schedule(deadline: .now() + 1, repeating: 1.0)
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
        browserDetected = !AXMeetClient.runningBrowserApps().isEmpty

        guard accessibilityTrusted else {
            meetDetected = false
            inCallDetected = false
            return
        }

        let sessions = axClient.findMeetSessions()
        meetDetected = !sessions.isEmpty

        // Do NOT reset automation eligibility when a session disappears from the
        // AX tree — window switches / unfocused windows make findMeetSessions
        // momentarily drop a still-open meeting, and resetting here is exactly what
        // caused re-recording on refocus. Eligibility is owned by MeetController's
        // armed-state model, flipped only by genuine pre-call ↔ in-call transitions.
        inCallDetected = sessions.contains { axClient.hasControl(AXMeetControls.leaveCall, in: $0) }

        guard MeetWatcher.isRecordingEnabled else { return }

        for session in sessions {
            attemptStartRecording(session: session, client: axClient)
        }
    }
}
