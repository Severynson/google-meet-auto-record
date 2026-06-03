## When the code of the app is updated - to apply changes do the following:

1. Quit running app + kill daemon:
   launchctl unload ~/Library/LaunchAgents/com.local.meetrecorder.plist 2>/dev/null
   pkill -f MeetRecorder

2. Reset stale accessibility grant:
   tccutil reset Accessibility com.local.meetrecorder

3. Remove old install:
   rm -rf /Applications/MeetRecorder.app

4. Ask the user to reinstall the app from DMG, and test.
