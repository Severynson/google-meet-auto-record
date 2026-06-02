# MeetRecorder

Automatically starts recording when you join a Google Meet call. Runs as a macOS menu bar app that installs itself as a login item.

**Requirements:**
- macOS 12+
- Google Workspace account with recording enabled (Business Starter or above)
- Chrome opened via the [accessibility-autoenabled-chrome-wrapper](https://github.com/your-repo/accessibility-autoenabled-chrome-wrapper) app, which launches Chrome with `--remote-debugging-port=9222`

---

## How it works

MeetRecorder polls Chrome every 3 seconds via Chrome DevTools Protocol (port 9222). When a `meet.google.com` tab is detected, it:

1. Clicks **More options** (⋮)
2. Clicks **Start recording**
3. In the confirmation panel: turns off captions, turns off transcript, enables Gemini notes
4. Clicks **Confirm**

All interaction uses stable `jsname` attributes from Meet's HTML — language-independent, works regardless of UI locale.

---

## Install

1. Download `MeetRecorder.dmg`
2. Open the DMG, drag `MeetRecorder.app` to **Applications**
3. Launch `MeetRecorder` from Applications or Spotlight

On first launch, the status window appears. Click **Install login item** — MeetRecorder will start automatically on every login from then on.

---

## Status window

Click the menu bar icon (●) to open it.

| Row | Meaning |
|---|---|
| Chrome CDP | Whether Chrome is running with debug port 9222 open |
| Login item | Whether MeetRecorder is installed as a login item |
| Last recording | Time of the most recent auto-started recording |

**Buttons change based on state:**

| Login item state | Buttons shown |
|---|---|
| Not installed | Install login item |
| Installed & running | Disable · Uninstall |
| Installed (disabled) | Enable · Uninstall |

- **Disable** — stops the login item service but keeps it configured (easy to re-enable)
- **Uninstall** — removes the login item entirely

---

## Daily use

1. Open Chrome via the **accessibility wrapper app** (not directly from Dock)
2. MeetRecorder starts at login automatically — nothing else to do
3. Join any Google Meet call — recording starts within ~3 seconds

**Logs:** `~/Library/Logs/MeetRecorder.log`

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Chrome CDP: "Not detected" | Chrome was not opened via the wrapper app. Quit Chrome, relaunch via wrapper. |
| Recording doesn't start | Meet UI still loading — retries every 3s automatically. Check log for errors. |
| "Start recording item not found" | Account lacks recording permission (requires Google Workspace). |
| Second launch does nothing | Correct — duplicate detection is intentional. Existing instance receives focus signal. |

---

## Build from source

```bash
cd MeetRecorder
bash build.sh          # produces MeetRecorder.app
bash package-dmg.sh    # wraps it in MeetRecorder.dmg
```

Requires Xcode Command Line Tools (`xcode-select --install`).
