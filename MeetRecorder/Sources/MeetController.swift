import Foundation

// Tracks meeting sessions we've triggered recording for (keyed by tab URL).
private var triggeredSessions = Set<String>()

// MARK: - jsname selectors (language-independent, from inspected HTML)

// More options button  — aria-label varies by locale, jsname does not
private let SEL_MORE_OPTIONS    = #"button[jsname="NakZHc"]"#

// "Start recording" menu item AND the confirm button in the panel — same jsname="A0ONe".
// First click: triggers the menu item (menu closes). Second click: confirms recording.
private let SEL_REC_BUTTON      = #"button[jsname="A0ONe"]"#

// Checkboxes in the recording confirmation panel (parent div jsnames from HTML)
private let SEL_CB_SUBTITLES    = #"[jsname="d9LF6c"] input[type="checkbox"]"#
private let SEL_CB_TRANSCRIPT   = #"[jsname="AXUMc"]  input[type="checkbox"]"#
private let SEL_CB_GEMINI       = #"[jsname="AqgVQe"] input[type="checkbox"]"#

private let JS_CLICK_CONFIRM = """
(function() {
  // After the menu item (A0ONe) is clicked the menu closes; the confirm panel
  // then renders another button[jsname="A0ONe"] — click it.
  const btns = Array.from(document.querySelectorAll('button[jsname="A0ONe"]'));
  // Pick the one that is NOT the "Start recording" trigger (already clicked) and is visible.
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

// Returns true if checkbox matching selector is currently checked.
private func jsIsChecked(_ selector: String) -> String {
    return "document.querySelector('\(selector)')?.checked ?? null"
}

// Sets checkbox to desired state without clicking if already correct.
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

// Returns true if element exists and is visible.
private func jsExists(_ selector: String) -> String {
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

func attemptStartRecording(tabURL: String) {
    guard tabURL.contains("meet.google.com") else { return }
    guard !triggeredSessions.contains(tabURL) else { return }

    guard let cdp = cdpClientForMeetTab() else {
        Logger.log("CDP: no Meet tab found (Chrome not running or --remote-debugging-port not set).")
        return
    }
    defer { cdp.disconnect() }

    Logger.log("CDP connected. Tab: \(tabURL)")

    // Step 1: verify More options button is present (meeting UI loaded)
    let exists = cdp.evaluate(jsExists(SEL_MORE_OPTIONS)) as? Bool ?? false
    guard exists else {
        Logger.log("More options button not found — Meet UI not ready yet.")
        return
    }

    // Step 2: click More options
    let r1 = cdp.evaluate(jsClick(SEL_MORE_OPTIONS)) as? String ?? "nil"
    Logger.log("Click more options → \(r1)")
    guard r1 == "ok" else { return }

    Thread.sleep(forTimeInterval: 0.6)

    // Step 3: click Start recording menu item (jsname="A0ONe", first occurrence)
    let r2 = cdp.evaluate(jsClick(SEL_REC_BUTTON)) as? String ?? "nil"
    Logger.log("Click start recording → \(r2)")
    guard r2 == "ok" else {
        Logger.log("Start recording item not found — account may lack recording permission.")
        return
    }

    Thread.sleep(forTimeInterval: 0.8)

    // Step 4: set checkboxes in confirmation panel
    let s1 = cdp.evaluate(jsSetCheckbox(SEL_CB_SUBTITLES,  checked: false)) as? String ?? "nil"
    let s2 = cdp.evaluate(jsSetCheckbox(SEL_CB_TRANSCRIPT, checked: false)) as? String ?? "nil"
    let s3 = cdp.evaluate(jsSetCheckbox(SEL_CB_GEMINI,     checked: true))  as? String ?? "nil"
    Logger.log("Checkboxes — subtitles:\(s1) transcript:\(s2) gemini:\(s3)")

    Thread.sleep(forTimeInterval: 0.3)

    // Step 5: click the confirm button
    let r3 = cdp.evaluate(JS_CLICK_CONFIRM) as? String ?? "nil"
    Logger.log("Click confirm → \(r3)")

    if r3.hasPrefix("ok") {
        triggeredSessions.insert(tabURL)
        Logger.log("Recording started for \(tabURL)")
    } else {
        Logger.log("Confirm step failed (\(r3)). Check log and update SEL_CONFIRM or JS_CLICK_CONFIRM.")
    }
}

func clearSession(key: String) {
    triggeredSessions.remove(key)
    Logger.log("Session cleared: \(key)")
}
