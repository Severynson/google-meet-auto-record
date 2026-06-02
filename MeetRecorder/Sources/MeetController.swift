import Foundation

// Tracks meeting sessions we've triggered recording for (keyed by tab URL).
// Only inserted after a successful or definitively-failed attempt — NOT while still in lobby.
private var triggeredSessions = Set<String>()

// Set by MeetWatcher to receive recording-started events.
var onRecordingStarted: ((String) -> Void)?

// MARK: - jsname selectors (language-independent, from inspected HTML)

// Present only in active meeting, not in pre-join lobby.
// End call button — unambiguous meeting-room indicator.
private let SEL_END_CALL        = #"button[jsname="CQylAd"]"#

// More options button (⋮) in call controls
private let SEL_MORE_OPTIONS    = #"button[jsname="NakZHc"]"#

// "Start recording" menu item AND the confirm button — same jsname="A0ONe".
// First click: menu item. Second click: confirm button in panel.
private let SEL_REC_BUTTON      = #"button[jsname="A0ONe"]"#

// Checkboxes in recording confirmation panel (parent div jsnames from HTML)
private let SEL_CB_SUBTITLES    = #"[jsname="d9LF6c"] input[type="checkbox"]"#
private let SEL_CB_TRANSCRIPT   = #"[jsname="AXUMc"]  input[type="checkbox"]"#
private let SEL_CB_GEMINI       = #"[jsname="AqgVQe"] input[type="checkbox"]"#

private let JS_CLICK_CONFIRM = """
(function() {
  // After menu item (A0ONe) is clicked, menu closes; confirm panel renders
  // another button[jsname="A0ONe"] — click the visible one.
  const btns = Array.from(document.querySelectorAll('button[jsname="A0ONe"]'));
  const confirmBtn = btns.find(b => {
    const rect = b.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  });
  if (!confirmBtn) return 'confirm_btn_not_found';
  confirmBtn.click();
  return 'ok:' + (confirmBtn.getAttribute('jslog') || '?');
})()
"""

// MARK: - JS helpers

private func jsClick(_ selector: String) -> String {
    return """
    (function() {
      const el = document.querySelector('\(selector)');
      if (!el) return 'not_found';
      el.click();
      return 'ok';
    })()
    """
}

private func jsSetCheckbox(_ selector: String, checked: Bool) -> String {
    return """
    (function() {
      const el = document.querySelector('\(selector)');
      if (!el) return 'not_found';
      if (el.checked !== \(checked)) { el.click(); return 'toggled'; }
      return 'already_\(checked)';
    })()
    """
}

private func jsIsVisible(_ selector: String) -> String {
    return """
    (function() {
      const el = document.querySelector('\(selector)');
      if (!el) return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    })()
    """
}

// MARK: - Main entry

// Returns true if the tab at `tabURL` is in an active meeting (not lobby).
// Called each poll cycle; does NOT mark the session as triggered.
func isMeetingActive(cdp: CDPClient) -> Bool {
    return cdp.evaluate(jsIsVisible(SEL_END_CALL)) as? Bool ?? false
}

func attemptStartRecording(tabURL: String) {
    guard tabURL.contains("meet.google.com") else { return }
    guard !triggeredSessions.contains(tabURL) else { return }

    guard let cdp = cdpClientForMeetTab() else {
        Logger.log("CDP: no Meet tab found. Chrome must be opened via wrapper app.")
        return
    }
    defer { cdp.disconnect() }

    // Phase 1: lobby check. End-call button only exists after joining.
    // If still in lobby, log and return — will retry on next poll.
    guard isMeetingActive(cdp: cdp) else {
        Logger.log("Tab \(tabURL): lobby detected, waiting for meeting to start.")
        return
    }

    Logger.log("Meeting active. Tab: \(tabURL)")

    // Phase 2: more options button must be present (call UI fully loaded)
    guard cdp.evaluate(jsIsVisible(SEL_MORE_OPTIONS)) as? Bool ?? false else {
        Logger.log("More options button not visible yet — call UI still loading.")
        return
    }

    // Phase 3: click More options
    let r1 = cdp.evaluate(jsClick(SEL_MORE_OPTIONS)) as? String ?? "nil"
    Logger.log("Click more options → \(r1)")
    guard r1 == "ok" else {
        Logger.log("Failed to click more options: \(r1)")
        markTried(tabURL) // avoid infinite loops on unexpected state
        return
    }

    Thread.sleep(forTimeInterval: 0.6)

    // Phase 4: click Start recording menu item
    let r2 = cdp.evaluate(jsClick(SEL_REC_BUTTON)) as? String ?? "nil"
    Logger.log("Click start recording → \(r2)")
    guard r2 == "ok" else {
        Logger.log("Start recording not found (\(r2)) — account may lack recording permission.")
        markTried(tabURL)
        return
    }

    Thread.sleep(forTimeInterval: 0.8)

    // Phase 5: set checkboxes in confirmation panel
    let s1 = cdp.evaluate(jsSetCheckbox(SEL_CB_SUBTITLES,  checked: false)) as? String ?? "nil"
    let s2 = cdp.evaluate(jsSetCheckbox(SEL_CB_TRANSCRIPT, checked: false)) as? String ?? "nil"
    let s3 = cdp.evaluate(jsSetCheckbox(SEL_CB_GEMINI,     checked: true))  as? String ?? "nil"
    Logger.log("Checkboxes — subtitles:\(s1) transcript:\(s2) gemini:\(s3)")

    Thread.sleep(forTimeInterval: 0.3)

    // Phase 6: click confirm button
    let r3 = cdp.evaluate(JS_CLICK_CONFIRM) as? String ?? "nil"
    Logger.log("Click confirm → \(r3)")

    if r3.hasPrefix("ok") {
        markTried(tabURL)
        Logger.log("Recording started for \(tabURL)")
        onRecordingStarted?(tabURL)
    } else {
        Logger.log("Confirm failed (\(r3)). Will not retry.")
        markTried(tabURL)
    }
}

private func markTried(_ url: String) {
    triggeredSessions.insert(url)
}

func clearSession(key: String) {
    triggeredSessions.remove(key)
    Logger.log("Session cleared: \(key)")
}
