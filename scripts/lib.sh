#!/usr/bin/env bash
# Shared helpers for install.sh and uninstall.sh. Sourced, never executed directly.
# Expects the caller to have run `set -euo pipefail`.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/.." && pwd)"

LABEL="com.pol.focus"
BRIDGE_PORT=47823
APP_DEST="$HOME/Applications/Focus.app"
# Two layouts. From source (Package.swift present): build.sh produces build/Focus.app.
# From a release folder: a prebuilt Focus.app sits next to scripts/ and nothing is built.
if [[ -f "$REPO_ROOT/Package.swift" ]]; then
  INSTALL_MODE="source"
  BUILD_APP="$REPO_ROOT/build/Focus.app"
else
  INSTALL_MODE="prebuilt"
  BUILD_APP="$REPO_ROOT/Focus.app"
fi
APP_EXEC="$APP_DEST/Contents/MacOS/Focus"
BUILD_EXEC="$BUILD_APP/Contents/MacOS/Focus"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DATA_DIR="$HOME/Library/Application Support/Focus"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Escape a string for use as a POSIX extended regex (pgrep -f).
escape_re() {
  printf '%s' "$1" | sed 's/[][\.^$*+?(){}|/]/\\&/g'
}

# PIDs of processes whose full command line starts with the given executable path.
pids_for() {
  pgrep -f "^$(escape_re "$1")( |\$)" 2>/dev/null || true
}

# PIDs of any Focus process we own, from either the installed or the build copy.
focus_pids() {
  {
    pids_for "$APP_EXEC"
    pids_for "$BUILD_EXEC"
  } | sort -u
}

# Remove one path if it exists. Prints it only when it was actually removed.
remove_path() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    if rm -rf -- "$p" 2>/dev/null; then
      echo "  removed $p"
    else
      echo "  could not remove $p (see scan below)" >&2
    fi
  fi
}

# Tell Launch Services to forget a bundle. Harmless if it was never registered.
unregister_bundle() {
  local app="$1"
  if [[ -x "$LSREGISTER" && -e "$app" ]]; then
    "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
  fi
}

# Poll a command once per 0.5s until it succeeds or the timeout (seconds) passes.
wait_for() {
  local timeout="$1"
  shift
  local tries=$((timeout * 2)) i
  for ((i = 0; i < tries; i++)); do
    if "$@"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

installed_running() {
  [[ -n "$(pids_for "$APP_EXEC")" ]]
}

bridge_listening() {
  lsof -nP -iTCP:"$BRIDGE_PORT" -sTCP:LISTEN 2>/dev/null |
    awk 'NR > 1 && $1 == "Focus" { found = 1 } END { exit !found }'
}

focus_ready() {
  installed_running && bridge_listening
}

# Stop the LaunchAgent and any running Focus process started from our two known paths.
stop_focus() {
  echo "==> Stopping Focus"
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true

  local i
  for ((i = 0; i < 10; i++)); do
    if [[ -z "$(focus_pids)" ]]; then
      break
    fi
    sleep 0.5
  done

  local pids pid
  pids="$(focus_pids)"
  if [[ -n "$pids" ]]; then
    echo "  process did not exit within 5s, sending SIGKILL"
    while read -r pid; do
      [[ -n "$pid" ]] || continue
      kill -9 "$pid" 2>/dev/null || true
      echo "  killed pid $pid"
    done <<< "$pids"
  else
    echo "  stopped"
  fi
}

# Remove every trace of a previous install, except the user's data (state and history), which is kept.
# Obsolete API key files from earlier versions are removed.
remove_app_traces() {
  echo "==> Removing old Focus traces"

  remove_path "$PLIST"

  if [[ -e "$APP_DEST" || -L "$APP_DEST" ]]; then
    unregister_bundle "$APP_DEST"
    remove_path "$APP_DEST"
  fi

  # Clear cfprefsd's cached copy first, then delete the file it would have written.
  if defaults read "$LABEL" >/dev/null 2>&1; then
    defaults delete "$LABEL" 2>/dev/null || true
    echo "  cleared defaults domain $LABEL"
  fi
  remove_path "$HOME/Library/Preferences/$LABEL.plist"
  remove_path "$HOME/Library/Caches/$LABEL"
  remove_path "$HOME/Library/HTTPStorages/$LABEL"
  remove_path "$HOME/Library/Saved Application State/$LABEL.savedState"
  remove_path "$HOME/Library/WebKit/$LABEL"
  remove_path "$HOME/Library/Application Scripts/$LABEL"
  remove_path "$HOME/Library/Containers/$LABEL"

  # HTTPStorages can carry suffixed bundle ids; an unmatched glob stays literal and is skipped.
  local f
  for f in "$HOME/Library/HTTPStorages/$LABEL"*; do
    if [[ "$f" != "$HOME/Library/HTTPStorages/$LABEL" ]]; then
      remove_path "$f"
    fi
  done

  remove_path "$DATA_DIR/apikey"
  remove_path "$DATA_DIR/apikey-gatekeeper"
  remove_path "$DATA_DIR/apikey-verifier"

  tccutil reset All "$LABEL" >/dev/null 2>&1 || true
  echo "  reset privacy (TCC) entries for $LABEL"
}

# Report anything left behind. Pass 1 as $1 to also check the data directory (uninstall).
# Returns 0 when clean, 1 when anything was found.
scan_traces() {
  local include_data="${1:-0}"
  local found=0 p f pids pid

  local candidates=(
    "$PLIST"
    "$APP_DEST"
    "$HOME/Library/Preferences/$LABEL.plist"
    "$HOME/Library/Caches/$LABEL"
    "$HOME/Library/Saved Application State/$LABEL.savedState"
    "$HOME/Library/WebKit/$LABEL"
    "$HOME/Library/Application Scripts/$LABEL"
    "$HOME/Library/Containers/$LABEL"
    "$HOME/Library/HTTPStorages/$LABEL"
    "$DATA_DIR/apikey"
    "$DATA_DIR/apikey-gatekeeper"
    "$DATA_DIR/apikey-verifier"
  )
  for f in "$HOME/Library/HTTPStorages/$LABEL"*; do
    if [[ -e "$f" ]]; then
      candidates+=("$f")
    fi
  done
  if [[ "$include_data" == "1" ]]; then
    candidates+=("$DATA_DIR")
  fi

  for p in "${candidates[@]}"; do
    if [[ -e "$p" || -L "$p" ]]; then
      echo "  leftover: $p"
      found=1
    fi
  done

  pids="$(focus_pids)"
  if [[ -n "$pids" ]]; then
    while read -r pid; do
      [[ -n "$pid" ]] || continue
      echo "  running: Focus pid $pid"
      found=1
    done <<< "$pids"
  fi

  if [[ "$found" -eq 0 ]]; then
    echo "No leftover traces."
    return 0
  fi
  return 1
}
