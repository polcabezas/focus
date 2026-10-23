#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) echo "Usage: uninstall.sh [--force]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

MARKER="$DATA_DIR/active-block-until"

if [[ "$FORCE" -eq 0 && -f "$MARKER" ]]; then
  raw="$(tr -d '[:space:]' < "$MARKER" || true)"
  if [[ -n "$raw" ]]; then
    until_epoch="$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$raw" +%s 2>/dev/null || true)"
    if [[ -z "$until_epoch" ]]; then
      echo "Focus: cannot read the block marker ($MARKER). Refusing to uninstall." >&2
      echo "Run with --force to uninstall anyway." >&2
      exit 1
    fi
    if [[ "$until_epoch" -gt "$(date +%s)" ]]; then
      echo "Focus is blocking until $(date -r "$until_epoch" '+%H:%M %Z' 2>/dev/null || echo "$raw")." >&2
      echo "Uninstall is refused during an active block. Run with --force to override." >&2
      exit 1
    fi
  fi
fi

stop_focus
remove_app_traces

echo "==> Removing data directory"
remove_path "$DATA_DIR"

unregister_bundle "$BUILD_APP"

echo "==> Checking for leftovers"
scan_status=0
scan_traces 1 || scan_status=$?

cat <<NEXT

Focus has been uninstalled.
Remove the browser extension manually:
  Arc:    arc://extensions > Focus > Remove
  Search: extension settings > remove Focus
The repository's build/ folder (if any) can be deleted with the repo.
NEXT

if [[ "$scan_status" -ne 0 ]]; then
  echo "Some traces above remain. Remove them by hand, then re-run this script to confirm." >&2
  exit 1
fi
