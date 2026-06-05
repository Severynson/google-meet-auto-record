import Foundation

// Tracks meeting sessions we've already attempted automation for.
// The flow is "try once": once "more options" appears we run the full click
// sequence a single time and never retry that session, success or failure.
private var triggeredSessions = Set<String>()
private let renderWaitTimeout: TimeInterval = 3.0
private let renderPollInterval: TimeInterval = 0.05

// Set by MeetWatcher to receive recording-started events.
var onRecordingStarted: ((String) -> Void)?

// Set by MeetWatcher to surface the latest automation status/error in the UI.
var onAutomationStatus: ((String) -> Void)?

func attemptStartRecording(session: AXMeetSession, client: AXMeetClient) {
    guard !triggeredSessions.contains(session.key) else { return }

    if client.isRecordingActive(in: session) {
        markTried(session.key)
        Logger.log("Skip automation: meeting already recording for: \(session.title)")
        onAutomationStatus?("Recording already active")
        return
    }

    // Gate: lobby and live call share the same URL. Wait for the "Leave call"
    // button (Завершити дзвінок) which only appears once inside an active call.
    // "More options" is also present in the waiting room, so it can't be used
    // as a reliable signal. MeetWatcher re-polls every second.
    guard client.hasControl(AXMeetControls.leaveCall, in: session) else {
        Logger.log("Meet window \(session.title): not in call yet, waiting for '\(AXMeetControls.leaveCall.titles.first ?? "leave call")'.")
        return
    }

    // Controls present → single attempt. Mark tried up front so a failure never retries.
    markTried(session.key)
    Logger.log("Controls detected. Starting recording automation for: \(session.title)")
    onAutomationStatus?("Meeting detected — starting recording…")

    runRecordingFlow(session: session, client: client)
}

private func runRecordingFlow(session: AXMeetSession, client: AXMeetClient) {
    if client.isRecordingActive(in: session) {
        Logger.log("Skip automation flow: meeting already recording for: \(session.title)")
        onAutomationStatus?("Recording already active")
        return
    }

    // 1. Click "more options" (Інші опції).
    let r1 = clickWhenRendered(client: client, control: AXMeetControls.moreOptions, in: session)
    Logger.log("Click more options → \(r1)")
    guard r1 == "ok" else {
        fail("Could not open the more-options menu (\(r1)).")
        return
    }

    // 2. Click "manage recording" menu item (Керувати записом).
    let r2 = clickWhenRendered(client: client, control: AXMeetControls.manageRecording, in: session)
    Logger.log("Click manage recording → \(r2)")
    guard r2 == "ok" else {
        fail("Could not open the recording panel (\(r2)) — account may lack recording permission.")
        return
    }

    guard waitForControl(client: client, control: AXMeetControls.startRecording, in: session, reason: "recording panel") else {
        fail("Recording panel did not render within \(renderWaitTimeout)s after Manage recording.")
        return
    }

    // 3-5. Set the optional toggles before confirming.
    let s1 = setOptionalCheckbox(client: client, control: AXMeetControls.subtitles, in: session, checked: false)
    let s2 = setOptionalCheckbox(client: client, control: AXMeetControls.transcript, in: session, checked: false)
    let s3 = setOptionalCheckbox(client: client, control: AXMeetControls.gemini, in: session, checked: true)
    Logger.log("Checkboxes — subtitles:\(s1) transcript:\(s2) gemini:\(s3)")

    // 6. Click "start recording" button (Почати запис) — opens consent dialog.
    let r3 = clickWhenRendered(client: client, control: AXMeetControls.startRecording, in: session)
    Logger.log("Click start recording → \(r3)")
    guard r3 == "ok" else {
        fail("Could not click Start recording (\(r3)).")
        return
    }

    // 7. Click "Почати" (Start) in the consent dialog to confirm.
    let r4 = clickWhenRendered(client: client, control: AXMeetControls.confirmStart, in: session)
    Logger.log("Click confirm start → \(r4)")

    if r4 == "ok" {
        Logger.log("Recording started for \(session.title)")
        onRecordingStarted?(session.key)
        onAutomationStatus?("Recording started ✓")
    } else {
        fail("Could not click confirm Start (\(r4)) — consent dialog may not have appeared.")
    }
}

private func fail(_ message: String) {
    Logger.log("Automation failed: \(message)")
    onAutomationStatus?("Automation failed: \(message)")
}

private func setOptionalCheckbox(client: AXMeetClient, control: AXControlTitles, in session: AXMeetSession, checked: Bool) -> String {
    let result = client.setCheckbox(control, in: session, checked: checked)
    return result == "not_found" ? "skipped_not_found" : result
}

private func clickWhenRendered(client: AXMeetClient, control: AXControlTitles, in session: AXMeetSession) -> String {
    guard waitForControl(client: client, control: control, in: session, reason: "click") else {
        return "render_timeout"
    }
    return client.click(control, in: session)
}

private func waitForControl(client: AXMeetClient, control: AXControlTitles, in session: AXMeetSession, reason: String) -> Bool {
    let start = Date()

    while Date().timeIntervalSince(start) <= renderWaitTimeout {
        if client.hasControl(control, in: session) {
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            Logger.log("AX wait \(control.name) for \(reason) → rendered after \(elapsed)s")
            return true
        }
        Thread.sleep(forTimeInterval: renderPollInterval)
    }

    Logger.log("AX wait \(control.name) for \(reason) → timeout after \(renderWaitTimeout)s session='\(session.title)'")
    return false
}

private func markTried(_ key: String) {
    triggeredSessions.insert(key)
}

func clearSession(key: String) {
    triggeredSessions.remove(key)
    Logger.log("Session cleared: \(key)")
}
