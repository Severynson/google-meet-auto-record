import Foundation

// Tracks meeting sessions we've triggered recording for.
// Only inserted after a successful or definitively-failed attempt — NOT while still in lobby.
private var triggeredSessions = Set<String>()

// Set by MeetWatcher to receive recording-started events.
var onRecordingStarted: ((String) -> Void)?

func isMeetingActive(session: AXMeetSession, client: AXMeetClient) -> Bool {
    client.isMeetingActive(session)
}

func attemptStartRecording(session: AXMeetSession, client: AXMeetClient) {
    guard !triggeredSessions.contains(session.key) else { return }

    guard isMeetingActive(session: session, client: client) else {
        Logger.log("Meet window \(session.title): lobby detected, waiting for meeting to start.")
        return
    }

    Logger.log("Meeting active. Window: \(session.title)")

    let r1 = client.click(AXMeetControls.moreOptions, in: session)
    Logger.log("Click more options → \(r1)")
    guard r1 == "ok" else {
        Logger.log("Failed to click more options: \(r1), will retry next poll.")
        return
    }

    Thread.sleep(forTimeInterval: 0.7)

    let r2 = client.click(AXMeetControls.startRecording, in: session)
    Logger.log("Click start recording → \(r2)")
    guard r2 == "ok" else {
        Logger.log("Start recording not found (\(r2)) — account may lack recording permission or title list needs update.")
        if isDefinitiveFailure(r2) {
            markTried(session.key)
        }
        return
    }

    Thread.sleep(forTimeInterval: 0.9)

    let s1 = setOptionalCheckbox(client: client, control: AXMeetControls.subtitles, in: session, checked: false)
    let s2 = setOptionalCheckbox(client: client, control: AXMeetControls.transcript, in: session, checked: false)
    let s3 = setOptionalCheckbox(client: client, control: AXMeetControls.gemini, in: session, checked: true)
    Logger.log("Checkboxes — subtitles:\(s1) transcript:\(s2) gemini:\(s3)")

    Thread.sleep(forTimeInterval: 0.3)

    let r3 = client.click(AXMeetControls.startRecording, in: session)
    Logger.log("Click confirm → \(r3)")

    if r3 == "ok" {
        markTried(session.key)
        Logger.log("Recording started for \(session.title)")
        onRecordingStarted?(session.key)
    } else {
        Logger.log("Confirm failed (\(r3)).")
        if isDefinitiveFailure(r3) {
            markTried(session.key)
        }
    }
}

private func setOptionalCheckbox(client: AXMeetClient, control: AXControlTitles, in session: AXMeetSession, checked: Bool) -> String {
    let result = client.setCheckbox(control, in: session, checked: checked)
    return result == "not_found" ? "skipped_not_found" : result
}

private func isDefinitiveFailure(_ result: String) -> Bool {
    result == "not_found"
}

private func markTried(_ key: String) {
    triggeredSessions.insert(key)
}

func clearSession(key: String) {
    triggeredSessions.remove(key)
    Logger.log("Session cleared: \(key)")
}
