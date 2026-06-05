## Changes tracking

- Read @CHANGELOG.md when fixing a bug, investigating why something broke, or understanding behavior that changed after recent edits.

- Update @CHANGELOG.md after introducing major project changes.

- When updating @CHANGELOG.md, tie changes to the current Git state:
  - If changes are already committed, record them under the relevant commit hash.
  - If changes are uncommitted or untracked, record them under an `Uncommitted changes` section.
  - At the start of a new task, check whether the previous `Uncommitted changes` section now corresponds to a real commit. If so, rename/move that section under the new commit hash before adding new entries.

## Code Conventions

A single source of truth for titles of components / buttons which we monitor to understand the state of the app, or automate clicks is @MeetRecorder/buttons.json. Any fallbacks must not be stored in the code.

## When the code of the app is updated - to apply changes do the following:

1. Quit running app + kill daemon:
   launchctl unload ~/Library/LaunchAgents/com.local.meetrecorder.plist 2>/dev/null
   pkill -f MeetRecorder

2. Reset stale accessibility grant:
   tccutil reset Accessibility com.local.meetrecorder

3. Remove old install:
   rm -rf /Applications/MeetRecorder.app

4. Ask the user to reinstall the app from DMG, and test.
