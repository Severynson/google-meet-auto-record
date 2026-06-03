# MeetRecorder

Automatically starts recording when you join a Google Meet call. Runs as a macOS menu bar app that installs itself as a login item.

**Requirements:**
- macOS 12+
- Google Workspace account with recording enabled (Business Starter or above)
- Accessibility permission for `MeetRecorder`
- Google Chrome, Chrome Beta/Dev/Canary, or Chromium

---

## How it works

MeetRecorder polls Chrome every 3 seconds through macOS Accessibility. When an active Google Meet window is detected, it:

1. Clicks **More options** (⋮)
2. Clicks **Start recording**
3. In the confirmation panel: turns off captions, turns off transcript, enables Gemini notes
4. Clicks **Confirm**

Element lookup uses the Chrome accessibility tree: roles, accessible names, and localized title lists. The actual interaction is a real macOS mouse click at the element bounds, not JavaScript DOM clicking and not Chrome DevTools Protocol.

---

## Install

1. Download `MeetRecorder.dmg`
2. Open the DMG, drag `MeetRecorder.app` to **Applications**
3. Launch `MeetRecorder` from Applications or Spotlight

On first launch, macOS may ask for Accessibility permission. Enable `MeetRecorder` in **System Settings → Privacy & Security → Accessibility**.

---

## Status window

Click the menu bar icon (●) to open it.

| Row | Meaning |
|---|---|
| Status text | Accessibility, Chrome, and Google Meet detection state |
| Auto-record meetings | Enables or disables automatic recording |

Use **Quit** to stop the running menu bar app.

---

## Daily use

1. Open Chrome normally
2. MeetRecorder starts at login automatically
3. Join any Google Meet call — recording starts within ~3 seconds after active-call controls appear

**Logs:** `~/Library/Logs/MeetRecorder.log`

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Accessibility permission required | Enable MeetRecorder in System Settings → Privacy & Security → Accessibility. |
| Chrome not detected | Open Chrome normally. No wrapper or debug port is required. |
| Recording doesn't start | Meet UI still loading — retries every 3s automatically. Check log for errors. |
| "Start recording item not found" | Account lacks recording permission, title list needs another locale string, or Meet changed accessible labels. |
| Second launch does nothing | Correct — duplicate detection is intentional. Existing instance receives focus signal. |

---

## Build from source

```bash
cd MeetRecorder
bash build.sh          # produces MeetRecorder.app
bash package-dmg.sh    # wraps it in MeetRecorder.dmg
```

Requires Xcode Command Line Tools (`xcode-select --install`).
