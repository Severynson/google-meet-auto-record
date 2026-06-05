import Foundation

// The "new_meeting" flag, per session (keyed by stable room code).
// A session is ARMED (eligible for automation) only after it is observed in a
// pre-call state: Meet open but NO "Leave call" button = waiting room, or the
// post-call screen after the user ended the previous call. That is the only
// moment a *new* meeting can begin.
//
// Eligibility is NEVER recomputed from live UI on every poll — it is flipped by
// exactly two explicit transitions:
//   1. armed   = true  when a pre-call state (no leaveCall) is seen.
//   2. armed   = false when the recording flow runs for that session.
// So window switches / refocus / momentary AX-tree flicker (session vanishing
// then reappearing, or the call UI dropping out of an unfocused window) do NOT
// re-arm and do NOT re-trigger. Only genuinely re-entering a pre-call state does.
private var armedSessions = Set<String>()
private let renderWaitTimeout: TimeInterval = 3.0
private let renderPollInterval: TimeInterval = 0.05
// Google Meet inserts controls into the AX tree before they are interactive
// (dropdown still animating / JS handler not yet wired). Pressing during that
// window returns AXSuccess but does nothing. Settle after render before pressing.
private let settleAfterRender: TimeInterval = 0.5

// Set by MeetWatcher to receive recording-started events.
var onRecordingStarted: ((String) -> Void)?

// Set by MeetWatcher to surface the latest automation status/error in the UI.
var onAutomationStatus: ((String) -> Void)?

func attemptStartRecording(session: AXMeetSession, client: AXMeetClient) {
    // Lobby and live call share the same URL. The "Leave call" button
    // (Завершити дзвінок) only exists inside an active call, so its absence
    // means waiting room or post-call screen — i.e. a new meeting attempt.
    let inCall = client.hasControl(AXMeetControls.leaveCall, in: session)

    guard inCall else {
        // Pre-call state → arm (set new_meeting = true) so automation fires once
        // the user joins. Nothing to click yet. MeetWatcher re-polls every second.
        if armedSessions.insert(session.key).inserted {
            Logger.log("New meeting armed (no leave-call button yet) for: \(session.title)")
        }
        return
    }

    // In an active call. Only proceed if this meeting was armed while pre-call.
    // If not armed we are returning to an already-handled call (e.g. user stopped
    // recording then switched windows) — never re-record it.
    guard armedSessions.contains(session.key) else { return }

    if client.isRecordingActive(in: session) {
        armedSessions.remove(session.key)
        Logger.log("Skip automation: meeting already recording for: \(session.title)")
        onAutomationStatus?("Recording already active")
        return
    }

    // Disarm up front (new_meeting = false) so a failure never retries this meeting.
    armedSessions.remove(session.key)
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
    Thread.sleep(forTimeInterval: settleAfterRender)

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

// Wait for the control to appear (fast path, up to renderWaitTimeout for slow renders),
// then settle so it becomes interactive before pressing. AX presence precedes interactivity.
private func clickWhenRendered(client: AXMeetClient, control: AXControlTitles, in session: AXMeetSession) -> String {
    guard waitForControl(client: client, control: control, in: session, reason: "click") else {
        return "render_timeout"
    }
    Thread.sleep(forTimeInterval: settleAfterRender)
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

