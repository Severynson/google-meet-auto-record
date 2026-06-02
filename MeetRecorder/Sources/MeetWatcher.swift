import Foundation

final class MeetWatcher {
    // Persisted toggle — the only user-facing control.
    static var isRecordingEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "recordingDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "recordingDisabled") }
    }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.local.meetrecorder.watcher", qos: .utility)

    private(set) var chromeDetected = false
    private(set) var lastRecordingTime: Date?

    private var lastSeenTabURLs = Set<String>()

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
        let tabs = fetchChromeTabs()
        chromeDetected = !tabs.isEmpty

        let meetURLs = Set(tabs.filter { $0.url.contains("meet.google.com") }.map { $0.url })

        let closed = lastSeenTabURLs.subtracting(meetURLs)
        for url in closed { clearSession(key: url) }
        lastSeenTabURLs = meetURLs

        guard MeetWatcher.isRecordingEnabled else { return }

        for url in meetURLs {
            attemptStartRecording(tabURL: url)
        }
    }
}
