# Changelog

## [Unreleased]

### Changed
- `MeetController`: fixed `Thread.sleep` delays replaced with AX-polling (`waitForControl` / `clickWhenRendered`, 3 s timeout, 50 ms poll interval) — each step fires as soon as the element appears in the AX tree instead of waiting a fixed duration.
- `ButtonConfig`: removed soft fallback defaults; missing or corrupt `buttons.json` now crashes immediately with `fatalError` instead of silently degrading.
- `ButtonConfig` / `AXMeetClient`: hardcoded `recordingStatusTexts` array moved to `buttons.json` under the `recordingActive` key — single source of truth.

### Added
- `buttons.json`: `recordingActive` key with multilingual strings used to detect an already-recording meeting via AX text search.
- `AGENTS.md`: convention — `buttons.json` is the single source of truth for all button/status labels; no fallbacks in code.

---

## 2026-06-04

### Fixed
- **Re-recording bug** (`c6ae049`): automation no longer re-triggers when joining a meeting that is already being recorded. `isRecordingActive()` checks both the window title and AX text; session key now uses the stable meet room code (`abc-defg-hij`) extracted by regex instead of the full window title, so identity survives title changes.
- **Automation restart on window refocus** (`fb5c813`): spurious status window popup on daemon re-launch / macOS login suppressed. Window is shown only on explicit user launch; suppressed when daemon relaunches within 120 s or at system startup.

---

## 2026-06-03

### Added
- **Multi-browser support** (`a00957c`): app now watches Chrome, Safari, Firefox, Opera, Brave, Arc, Comet (Perplexity), and ChatGPT Atlas. `runningChromeApps()` renamed to `runningBrowserApps()`. Status strings updated ("Browser detected", "No supported browser detected").
- **`buttons.json`** (`c55e2fd`): external config file for all Meet control accessible names; survives app rebuilds, no recompile needed to adjust labels.
- **Full automation flow** (`2abb78a`): added step 7 — confirm-start click in the consent dialog, completing end-to-end recording start.

### Changed
- **Core rewrite: CDP → Accessibility API** (`c55e2fd`, `977bd14`): replaced Chrome DevTools Protocol automation with macOS Accessibility API (`AXUIElement`). Works with any browser without a debugging port. `AXManualAccessibility` + `AXEnhancedUserInterface` attributes enable web content exposure in Chromium-based browsers; harmless on Safari/Firefox.
- **AX robustness** (`ae0315d`): two-pass element search (window first, then appRoot with frame filter); frame-based filtering prevents false positives from off-screen AX nodes; browser chrome noise filter (bookmarks, URLs) prevents mis-clicks.
- **Multilingual button labels expanded** (`850299e`): `buttons.json` extended with Russian and Georgian variants for all controls.
- **`ButtonConfig.swift`**: loads labels from `buttons.json` at startup; all automation targets and checkbox states driven from config.
- **`build.sh`**: universal binary (arm64 + x86_64 via `lipo`), automatic code signing with stable identity (accessibility grant survives rebuilds), icon generation from PNG source.
- **`StatusWindowController`**: full UI overhaul — in-call detection, automation status line, accessibility grant flow, "Kill bg process" action.

### Removed
- `CDPClient.swift` and `ChromeLauncher` helper app (CDP approach).
- Built-in fallback button label defaults in `ButtonConfig`.

---

## 2026-06-02

### Added
- **App bundle** (`a94b919`): restructured as `MeetRecorder.app`; added `AppDelegate`, `MeetWatcher`, `StatusWindowController`, `StatusBarController`, `LaunchAgentManager`, `package-dmg.sh`.
- **Initial prototype** (`b00d2d4`): CDP-based Meet detection and recording automation; `CDPClient.swift`, `MeetController.swift`, `Logger.swift`.
