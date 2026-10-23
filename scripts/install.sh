#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) echo "Usage: install.sh [--dry-run]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Focus install plan (dry run, nothing was changed)"
  if [[ "$INSTALL_MODE" == "source" ]]; then
    echo "  layout:     source (Package.swift found)"
    echo "  app:        built by scripts/build.sh into $BUILD_APP"
  else
    echo "  layout:     prebuilt release folder (no Package.swift)"
    echo "  app:        prebuilt $BUILD_APP (no build)"
    if [[ ! -d "$BUILD_APP" ]]; then
      echo "  ERROR: no Focus.app next to scripts/ ($BUILD_APP)"
      exit 1
    fi
    if codesign --verify --deep --strict "$BUILD_APP" 2>/dev/null; then
      echo "  signature:  valid"
    else
      echo "  signature:  INVALID (a real install would stop here)"
    fi
    echo "  quarantine: would remove com.apple.quarantine from $BUILD_APP"
  fi
  echo "  stop:       bootout gui/$UID/$LABEL and stop Focus processes from $APP_DEST and $BUILD_EXEC"
  echo "  remove:     old LaunchAgent, $APP_DEST, old preferences and caches (state and history are kept)"
  echo "  install:    $BUILD_APP -> $APP_DEST"
  echo "  launch:     $PLIST (RunAtLoad), launchctl bootstrap gui/$UID"
  echo "  verify:     bridge listening on 127.0.0.1:$BRIDGE_PORT within 10s"
  exit 0
fi

# 1. Get the app: build it (source layout) or use the prebuilt copy (release folder).
# Nothing on the machine is touched if this fails.
if [[ "$INSTALL_MODE" == "source" ]]; then
  echo "==> Building"
  if ! "$REPO_ROOT/scripts/build.sh"; then
    echo "Build failed. Nothing was installed or changed." >&2
    exit 1
  fi
else
  echo "==> Using prebuilt Focus.app (no build)"
  if [[ ! -d "$BUILD_APP" ]]; then
    echo "No Focus.app next to scripts/ ($BUILD_APP). Nothing was installed or changed." >&2
    exit 1
  fi
  if ! codesign --verify --deep --strict "$BUILD_APP" 2>/dev/null; then
    echo "Prebuilt Focus.app failed its code signature check. Nothing was installed or changed." >&2
    exit 1
  fi
  xattr -dr com.apple.quarantine "$BUILD_APP" 2>/dev/null || true
  echo "  removed the com.apple.quarantine attribute from $BUILD_APP (if it was set)"
fi

# 2. Stop the running agent and any Focus process from the known paths.
stop_focus

# 3. Remove traces of any previous install (keeps state and history).
remove_app_traces

# 4. Copy the app (fresh build or prebuilt) into place.
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
