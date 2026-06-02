# google-meet-auto-record

Automatically starts recording when you join a Google Meet call. No extensions, no bots — uses Chrome's built-in remote debugging API to click the native Meet UI on your behalf.

**Requirements:**
- macOS
- Google Workspace account with recording enabled (basic plan or above)
- Google Chrome installed in `/Applications`

---

## How it works

1. **ChromeLauncher** — a `.app` wrapper that opens Chrome with `--remote-debugging-port=9222`. This exposes a local WebSocket API (Chrome DevTools Protocol) that MeetRecorder uses to control the page.
2. **MeetRecorder** — a background process that polls Chrome every 3 seconds. When it detects a `meet.google.com` tab, it clicks: **More options → Start recording → confirms** (subtitles off, transcript off, Gemini notes on).

Nothing leaves your machine. Port 9222 is bound to `localhost` only.

---

## Setup (one-time)

### 1. Build ChromeLauncher

```bash
cd ChromeLauncher
bash build.sh
```

This creates `ChromeLauncher.app` in that folder.

**Optional — make it look like Chrome in the Dock:**
1. Find Google Chrome in Finder (`/Applications`), press `Cmd+I`
2. Click the icon thumbnail in the top-left of the info panel, press `Cmd+C`
3. Press `Cmd+I` on `ChromeLauncher.app`, click its icon thumbnail, press `Cmd+V`

### 2. Add ChromeLauncher to the Dock

Drag `ChromeLauncher/ChromeLauncher.app` to your Dock. Remove the original Google Chrome from the Dock (right-click → Options → Remove from Dock) so you always open Chrome through the wrapper.

### 3. Build MeetRecorder

```bash
cd MeetRecorder
bash build.sh
```

This produces the `MeetRecorder` binary in that folder.

---

## Daily use

**Every time you want auto-recording:**

1. Open Chrome via **ChromeLauncher** (from the Dock). If Chrome is already open, quit it first — it must be launched with the debug port flag.
2. In a terminal, run:
   ```bash
   /path/to/MeetRecorder/MeetRecorder
   ```
3. Join your Google Meet call normally. Recording starts automatically within ~3 seconds of the meeting UI loading.

**To stop MeetRecorder:** press `Ctrl+C` in the terminal, or close the terminal window.

**Logs** are written to `~/Library/Logs/MeetRecorder.log` — check there if recording doesn't start.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "CDP: no Meet tab found" in logs | Chrome was not opened via ChromeLauncher. Quit Chrome, relaunch via ChromeLauncher. |
| Recording doesn't start, no error | Meet UI may still be loading — MeetRecorder retries every 3s automatically. |
| "Start recording item not found" | Your Google account lacks recording permission. Requires Google Workspace (Business Starter or above). |
| "confirm_btn_not_found" in logs | Meet UI changed. Open an issue with the HTML of the confirm button. |

---

## Recording settings applied automatically

| Setting | Value |
|---|---|
| Captions in recording | Off |
| Transcript | Off |
| Gemini notes | On |

These match the checkbox states from the recording confirmation panel.
