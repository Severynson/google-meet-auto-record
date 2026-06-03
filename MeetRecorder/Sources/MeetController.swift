import Foundation

// Tracks meeting sessions we've already attempted automation for.
// The flow is "try once": once "more options" appears we run the full click
// sequence a single time and never retry that session, success or failure.
private var triggeredSessions = Set<String>()

// Set by MeetWatcher to receive recording-started events.
var onRecordingStarted: ((String) -> Void)?

// Set by MeetWatcher to surface the latest automation status/error in the UI.
var onAutomationStatus: ((String) -> Void)?

func attemptStartRecording(session: AXMeetSession, client: AXMeetClient) {
    guard !triggeredSessions.contains(session.key) else { return }

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
    // 1. Click "more options" (Інші опції).
    let r1 = client.click(AXMeetControls.moreOptions, in: session)
    Logger.log("Click more options → \(r1)")
    guard r1 == "ok" else {
        fail("Could not open the more-options menu (\(r1)).")
        return
    }

    Thread.sleep(forTimeInterval: 0.7)

    // 2. Click "manage recording" menu item (Керувати записом).
    let r2 = client.click(AXMeetControls.manageRecording, in: session)
    Logger.log("Click manage recording → \(r2)")
    guard r2 == "ok" else {
        fail("Could not open the recording panel (\(r2)) — account may lack recording permission.")
        return
    }

    Thread.sleep(forTimeInterval: 0.9)

    // 3-5. Set the optional toggles before confirming.
    let s1 = setOptionalCheckbox(client: client, control: AXMeetControls.subtitles, in: session, checked: false)
    let s2 = setOptionalCheckbox(client: client, control: AXMeetControls.transcript, in: session, checked: false)
    let s3 = setOptionalCheckbox(client: client, control: AXMeetControls.gemini, in: session, checked: true)
    Logger.log("Checkboxes — subtitles:\(s1) transcript:\(s2) gemini:\(s3)")

    Thread.sleep(forTimeInterval: 0.3)

    // 6. Click "start recording" button (Почати запис) — opens consent dialog.
    let r3 = client.click(AXMeetControls.startRecording, in: session)
    Logger.log("Click start recording → \(r3)")
    guard r3 == "ok" else {
        fail("Could not click Start recording (\(r3)).")
        return
    }

    // Consent dialog "Переконайтеся, що всі готові" appears after a short delay.
    Thread.sleep(forTimeInterval: 0.8)

    // 7. Click "Почати" (Start) in the consent dialog to confirm.
    let r4 = client.click(AXMeetControls.confirmStart, in: session)
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

private func markTried(_ key: String) {
    triggeredSessions.insert(key)
}

func clearSession(key: String) {
    triggeredSessions.remove(key)
    Logger.log("Session cleared: \(key)")
}
