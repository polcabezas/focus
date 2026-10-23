# Focus

A macOS menu-bar app and browser extension that blocks distracting sites and apps during focus time.
It runs without root, installs only into your user account, and removes cleanly.

## Requirements

- macOS 26 or later
- Xcode or the Swift toolchain (Swift 6.2+)

## Install

```sh
./scripts/install.sh
```

This builds `build/Focus.app`, copies it to `~/Applications/Focus.app`, and starts it as a
LaunchAgent so it runs at login. If the build fails, nothing is changed.

Re-running the script is safe. It stops any running Focus, removes traces of the previous install
(old app, LaunchAgent, preferences, caches, and the obsolete API key files from earlier versions), and reinstalls.
Your state and history are kept. The script waits up to 10 s for the app to start and for the browser
bridge to listen on `127.0.0.1:47823`, and exits with an error if either does not happen.

Then load the browser extension (see below).

## Load the extension

- **Arc:** open `arc://extensions`, enable Developer mode, click Load unpacked, and choose the `extension/` folder.
- **Search:** open the extension settings and choose the `extension/` folder.

The extension talks to the app over `ws://127.0.0.1:47823`. Without the app it keeps enforcing the last rules it received until the block ends.
Focus recognizes a browser by the app that owns the extension's connection, not by the Origin or user agent the extension sends
(Search presents itself as Chrome). Origin is only a first filter.

## Troubleshooting

- **Browser keeps closing:** open the Focus menu. Each installed browser should show "Extension connected". If it says
  "Extension not connected", reload or re-load the extension in that browser. Focus warns for 20 s before closing a browser that
  has no extension connection.
- **Menu shows "Browser bridge isn't running":** check the app is listening with `lsof -nP -iTCP:47823`. The output should show
  Focus in LISTEN state. Focus retries every 5 s, so wait a moment or restart it.
- **Bridge logs:** run `log stream --predicate 'subsystem == "com.pol.focus"'` (use `/usr/bin/log` if your shell has another `log`).
  It shows each handshake's origin, the client pid and browser bundle id of each connection, the hello's user agent, and why each connection closed.
  The extension logs its connects, closes (with the close code) and applied rules to the browser's extension console.
- **Search keeps disconnecting:** WebKit suspends idle extension background scripts. The extension pings the app from each page you
  browse, so the connection returns as soon as you open a page; if it doesn't, reload the extension in Search.
- **Extension changes don't show up in Search:** Search copies the extension into
  `~/Library/Application Support/Search/Extensions/<id>/` when you add it, and "reload" doesn't re-import from the
  `extension/` folder. After any extension update, remove Focus in Search's extension settings and add the folder again.
  Arc's "Load unpacked" reads the folder directly, so reloading there is enough.
- **After any extension change, bump `version` in `extension/manifest.json`.** Search only refreshes its copy when the
  version changes, so an edit with the same version is not picked up even after re-adding the folder.

## Usage

- **Modes** group domains and apps (for example Work, Personal, Training).
- **Sessions** start a block now for 15 minutes, 30 minutes, 1 hour, 2 hours, 4 hours, a custom length, or until a clock time.
- **Schedules** repeat a block on chosen weekdays and times, including overnight ranges.
- While a block is active, you cannot shorten it, remove sites or apps from the blocked mode, or change the schedule that
  started it. Adding sites and apps is always allowed.
- **Emergency exit:** during a block you can end it early. You type a random phrase exactly, wait for the emergency wait
  time (15 minutes by default), then give a reason of at least 20 characters. This ends the current block.
  The wait, phrase length and whether emergency exit is enabled are set in Settings > General.
- While a block is active, Focus cannot be quit.

## Icon

The app icon is an Icon Composer source at `assets/AppIcon.icon`. Edit it in Icon Composer (Xcode > Open Developer Tool >
Icon Composer). `scripts/build.sh` compiles it with `actool` into the app's `Assets.car`, so there is nothing to regenerate
for the app. The browser extension PNGs are rasterized from `assets/extension/*.svg` by `bash assets/make-extension-icons.sh`.

## Uninstall

```sh
./scripts/uninstall.sh
```

Uninstall is refused while a block is active. `./scripts/uninstall.sh --force` overrides that.
The script is idempotent. It stops Focus, removes the app, LaunchAgent, data folder and macOS
preferences/caches, and prints each path it removed. It finishes with a leftover scan that lists anything
still present or still running, and exits non-zero if it finds any. Remove the extension manually in Arc and Search.

## Footprint

| Path | Created by | Removed by |
| --- | --- | --- |
| `~/Applications/Focus.app` | install.sh | uninstall.sh |
| `~/Library/LaunchAgents/com.pol.focus.plist` | install.sh | uninstall.sh |
| `~/Library/Application Support/Focus/` (state.json, history.jsonl, active-block-until) | the app | uninstall.sh |
| `~/Library/Application Support/Focus/apikey`, `apikey-gatekeeper`, `apikey-verifier` (obsolete key files) | an earlier version | install.sh and uninstall.sh |
| `~/Library/Preferences/com.pol.focus.plist` | macOS, only if created | install.sh (old traces) and uninstall.sh (defensive) |
| `~/Library/Caches/com.pol.focus/` | macOS networking, if created | install.sh (old traces) and uninstall.sh (defensive) |
| `~/Library/HTTPStorages/com.pol.focus*` | macOS networking, if created | install.sh (old traces) and uninstall.sh (defensive) |
| `~/Library/Saved Application State/com.pol.focus.savedState` | macOS, if created | install.sh (old traces) and uninstall.sh (defensive) |
| `~/Library/WebKit/com.pol.focus/` | macOS, if created | install.sh (old traces) and uninstall.sh (defensive) |
| `~/Library/Application Scripts/com.pol.focus/` | macOS, if created | install.sh (old traces) and uninstall.sh (defensive) |
| `~/Library/Containers/com.pol.focus/` | macOS, if created | install.sh (old traces) and uninstall.sh (defensive) |
| Privacy (TCC) permission entries | macOS, if the app requests any | `tccutil reset All com.pol.focus` in install.sh and uninstall.sh |
| `build/` in the repository | build.sh | delete the folder (or the repo) |
| Browser extension | you, when loading it | remove it in Arc / Search |

The app keeps everything in its own data folder, does not use UserDefaults, makes no network requests to any
service, and does not run as root.
