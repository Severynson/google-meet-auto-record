import Cocoa

func isChromeRunning() -> Bool {
    return NSWorkspace.shared.runningApplications
        .contains { $0.bundleIdentifier == "com.google.Chrome" }
}

var lastSeenTabURLs = Set<String>()

func poll() {
    guard isChromeRunning() else { return }

    // Tab URLs come from CDP /json/list — no AX tree walk needed for URL detection.
    let tabs = fetchChromeTabs()
    let meetURLs = Set(tabs.filter { $0.url.contains("meet.google.com") }.map { $0.url })

    // Detect tabs that were on Meet and are now gone → clear their sessions.
    let closed = lastSeenTabURLs.subtracting(meetURLs)
    for url in closed { clearSession(key: url) }
    lastSeenTabURLs = meetURLs

    for url in meetURLs {
        attemptStartRecording(tabURL: url)
    }
}

// ---- Entry point ----

Logger.log("MeetRecorder starting.")
Logger.log("CDP polling localhost:9222. Chrome must be launched via ChromeLauncher.")

let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in poll() }
RunLoop.main.run()
