#!/bin/bash
set -euo pipefail

REPO="/Users/ah/code/yagent"
DEMO_SRC="$REPO/screenshots/demo-repo/src"
OUTPUT="$REPO/screenshots/yagent-demo.png"
TMUX_SESSION="yagent-screenshot-$$"

# Clean up any existing tmux session
 tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
 rm -f "$OUTPUT"

# 1. Create a detached tmux session running yagent
 tmux new-session -d -s "$TMUX_SESSION" -c "$DEMO_SRC" \
     "export PATH=\"$REPO/bin:\$PATH\" YAGENT_YAZI_ID=screenshot$$; yagent ."

sleep 2

# 2. Open iTerm2 attached to this tmux session
WINID=$(osascript <<APPLESCRIPT
tell application "iTerm2"
    activate
    set newWindow to create window with default profile
    set winID to id of newWindow
    tell current session of newWindow
        write text "tmux attach -t $TMUX_SESSION"
    end tell
    delay 2
    return winID as string
end tell
APPLESCRIPT
)

WINID=$(echo "$WINID" | tr -d '\n')

sleep 1

# 3. Send 'j' to the tmux session to navigate to auth
 tmux send-keys -t "$TMUX_SESSION" j

sleep 0.5

# 4. Capture the iTerm window
if [ -n "$WINID" ] && [ "$WINID" -gt 0 ] 2>/dev/null; then
    screencapture -l "$WINID" "$OUTPUT" 2>/dev/null || screencapture "$OUTPUT"
else
    screencapture "$OUTPUT"
fi

echo "Screenshot saved to $OUTPUT"

# 5. Clean up: close iTerm window, kill tmux session
osascript <<CLOSESCRIPT 2>/dev/null || true
tell application "iTerm2"
    repeat with w in windows
        if id of w is $WINID then
            close w
            exit repeat
        end if
    end repeat
end tell
CLOSESCRIPT

 tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
