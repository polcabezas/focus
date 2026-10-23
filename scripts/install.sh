#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# 1. Build first. Nothing on the machine is touched if this fails.
echo "==> Building"
if ! "$REPO_ROOT/scripts/build.sh"; then
  echo "Build failed. Nothing was installed or changed." >&2
  exit 1
fi

# 2. Stop the running agent and any Focus process from the known paths.
stop_focus

# 3. Remove traces of any previous install (keeps state and history).
remove_app_traces

# 4. Copy the fresh build into place.
echo "==> Installing $APP_DEST"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
cp -R "$BUILD_APP" "$APP_DEST"
echo "  copied to $APP_DEST"

# Launch Services should only know the installed copy, not the repo build.
unregister_bundle "$BUILD_APP"

# 5. Write and validate the LaunchAgent.
echo "==> Writing $PLIST"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_EXEC</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST

if ! plutil -lint "$PLIST" >/dev/null; then
  echo "Generated LaunchAgent is invalid: $PLIST" >&2
  exit 1
fi

# 6. Start it.
echo "==> Starting Focus"
if ! launchctl bootstrap "gui/$UID" "$PLIST"; then
  echo "launchctl bootstrap failed. Inspect with: launchctl print gui/$UID/$LABEL" >&2
  exit 1
fi

# 7. Verify the process is up and the browser bridge is listening (up to 10s).
echo "==> Waiting for the browser bridge"
if ! wait_for 10 focus_ready; then
  if installed_running; then
    echo "ERROR: Focus is running but not listening on 127.0.0.1:$BRIDGE_PORT." >&2
    echo "Check with: lsof -nP -iTCP:$BRIDGE_PORT -sTCP:LISTEN" >&2
  else
    echo "ERROR: Focus did not start within 10s." >&2
    echo "Check with: launchctl print gui/$UID/$LABEL" >&2
  fi
  exit 1
fi
echo "  Bridge listening on 127.0.0.1:$BRIDGE_PORT"

cat <<NEXT

Focus is installed and running (menu-bar icon).

Next steps:
  1. Load the browser extension from $REPO_ROOT/extension
     Arc:    arc://extensions > Developer mode > Load unpacked > choose extension/
     Search: extension settings > choose the extension/ folder
NEXT
