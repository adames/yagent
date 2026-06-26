#!/bin/bash
osascript <<'APPLESCRIPT'
tell application "iTerm2"
    activate
    set newWindow to create window with default profile
    tell current session of newWindow
        write text "export PATH=\"/Users/ah/code/yagent/bin:$PATH\"; yagent /Users/ah/code/yagent/screenshots/demo-repo/src"
    end tell
end tell
APPLESCRIPT
