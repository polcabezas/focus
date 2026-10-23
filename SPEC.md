# Focus — build spec (shared contract)

macOS website/app blocker. One Swift menu-bar app (no root, no system files touched) + one plain-JS
browser extension. Simplicity and zero-trace removal are hard requirements. There is no AI, no network
access to any model provider, and no API keys.

**Rules for every contributor**
- Swift Package Manager only (no Xcode project). `Package.swift` already exists — do not change it.
- Zero third-party dependencies (Swift and JS).
- Never use `UserDefaults` / `@AppStorage` (creates ~/Library/Preferences plist). Never use a sandbox.
- Every NSWindow you create: `isRestorable = false`, `isReleasedWhenClosed = false`.
- Only write inside `~/Library/Application Support/Focus/` (via `Store`).
- Keep code small and plain. Few comments. No speculative features.

Bundle id: `com.pol.focus`. Data dir: `~/Library/Application Support/Focus/`. Bridge: `ws://127.0.0.1:47823`.

## Layout

```
Package.swift                         platforms macOS 26, Swift language mode 5
Sources/FocusCore/                    pure logic, no AppKit/SwiftUI imports
  Models.swift  Store.swift  Engine.swift  TrustedClock.swift
Tests/FocusCoreTests/                 EngineTests.swift, StoreTests.swift
Sources/Focus/App/FocusApp.swift      @main
Sources/Focus/System/                 AppController, AppBlocker, BridgeServer, OverlayController
Sources/Focus/UI/                     SwiftUI views: Theme, OverlayChrome, MenuContentView, SettingsView,
                                      BlockedView, BrowserWarningView, EmergencyView
extension/                            manifest.json, background.js, keepalive.js, blocked.html/.css/.js
scripts/                              build.sh, install.sh, uninstall.sh, lib.sh
```

## FocusCore — all `public`, structs `Codable, Equatable`

```swift
public enum TargetKind: String, Codable { case domain, app }
public struct Mode: Codable, Identifiable, Equatable {
    public var id: UUID; public var name: String; public var symbol: String   // SF Symbol name
    public var domains: [String]          // "youtube.com" (matches host == d or host ends with "." + d)
    public var appBundleIDs: [String]     // "com.hnc.Discord"
}
public struct Schedule: Codable, Identifiable, Equatable {
    public var id: UUID; public var modeID: UUID
    public var weekdays: Set<Int>         // Calendar weekday: 1 = Sunday ... 7 = Saturday
    public var startMinute: Int; public var endMinute: Int   // minutes from midnight; end < start wraps past midnight
    public var enabled: Bool
}
public struct Session: Codable, Identifiable, Equatable {          // manual block started from the menu
    public var id: UUID; public var modeID: UUID; public var start: Date; public var end: Date
}
public struct Settings: Codable, Equatable {
    public var emergencyEnabled = true
    public var emergencyWaitMinutes = 15
    public var emergencyPhraseLength = 200
    public var supportedBrowsers: [String: String]  // keys = allowed browser bundle ids; values ignored
    public var knownBrowsers: [String]              // browsers that are closed when not supported
}
public struct EmergencyRequest: Codable, Equatable { public var requestedAt: Date; public var phrase: String }
public struct ClockAnchor: Codable, Equatable { public var trusted: Date; public var monotonicNanos: UInt64 }
public struct AppState: Codable, Equatable {
    public var modes: [Mode]; public var schedules: [Schedule]; public var sessions: [Session]
    public var settings: Settings
    public var emergency: EmergencyRequest?        // pending emergency exit
    public var emergencyAt: Date?; public var overrideUntil: Date?   // blocks active at emergencyAt are ignored until overrideUntil
    public var clock: ClockAnchor?
    public static func seeded() -> AppState        // Work / Personal / Training modes with social/video domains
}
public enum HistoryEvent: Codable {
    case sessionStarted(modeID: UUID, minutes: Int)
    case emergencyUsed(reason: String)
    case editRejected(reason: String)
}
```

Every persisted struct decodes tolerantly (`decodeIfPresent` + default per field), so unknown keys are ignored and
missing keys get defaults. state.json files from older versions (with keys such as `grants`, `strictness`,
`purposefulLockedUntil`, `gatekeeper`) still decode.

**Store** — `public final class Store`
- `public static let directory: URL` (= ~/Library/Application Support/Focus, created on demand)
- `public func load() -> AppState` (decode `state.json`; missing → `.seeded()`; unreadable → moved to `state.json.corrupt-<unix ts>`, then `.seeded()`); `public func save(_: AppState)` (atomic)
- `public func append(_ event: HistoryEvent)` → one JSON line in `history.jsonl`
- `public func writeActiveBlockMarker(until: Date?)` → file `active-block-until` holding UTC ISO8601 text `yyyy-MM-ddTHH:mm:ssZ` (what uninstall.sh parses), or delete when nil

**TrustedClock** — `public enum TrustedClock`
- `public static func now(wall: Date = Date(), anchor: inout ClockAnchor?) -> Date`
  Monotonic source `clock_gettime_nsec_np(CLOCK_MONOTONIC)` (includes sleep). Same boot (monotonic ≥ anchor's):
  trusted = anchor.trusted + elapsed monotonic (ignores wall-clock jumps either direction). New boot or no anchor:
  trusted = max(wall, anchor?.trusted ?? wall). Update anchor each call.

**Engine** — `public enum Engine`, pure static funcs, every func takes `now: Date` (and `calendar: Calendar = .current`)
```swift
public struct ActiveBlock: Equatable { public var mode: Mode; public var start: Date; public var end: Date }
public enum Decision: Equatable { case allowed; case blocked(until: Date) }

static func activeBlocks(_ s: AppState, now: Date, calendar: Calendar = .current) -> [ActiveBlock]
    // manual sessions with start <= now < end + enabled schedule occurrences covering now (handle wrap past midnight,
    // weekday of the occurrence START); drop blocks whose start <= s.emergencyAt when now < s.overrideUntil
static func isBlockActive(_ s: AppState, now: Date) -> Bool
static func blockedDomains(_ s: AppState, now: Date) -> [String]     // union over active blocks
static func blockedApps(_ s: AppState, now: Date) -> [String]
static func decision(forHost host: String, _ s: AppState, now: Date) -> Decision
static func decision(forApp bundleID: String, _ s: AppState, now: Date) -> Decision
    // blocked(until: latest end) by the active blocks that match the host or app; otherwise allowed
static func applyEmergency(_ s: inout AppState, now: Date)
    // emergencyAt = now; overrideUntil = max end of activeBlocks; manual sessions active now get end = now; emergency = nil
static func validateEdit(old: AppState, new: AppState, now: Date) -> Bool
    // true if no block is active. During an active block reject (false) if: any domain/app removed from a mode used by an
    // active block; an active manual session removed or its end moved earlier; a schedule producing an active block
    // removed, disabled or changed; any of settings.emergencyEnabled/emergencyWaitMinutes/emergencyPhraseLength/
    // knownBrowsers/supportedBrowsers changed. Adding things is always allowed.
static func emergencyPhrase(length: Int) -> String   // random lowercase letters + digits, grouped by spaces every 5 chars
```

**TrustedClock / Engine time rules:** all block decisions use the trusted clock, so changing the wall clock does not end a block.

## App layer — `Sources/Focus/App`, `Sources/Focus/System`

**AppController** — `@MainActor final class AppController: ObservableObject` (views use it via `@EnvironmentObject var app: AppController`)
```swift
@Published private(set) var state: AppState
@Published private(set) var now: Date                 // trusted, ticks every 1s
@Published private(set) var connectedBrowsers: Set<String>  // bundle ids of verified browsers seen in the last 45s
@Published private(set) var browserSeen: [String: Date]     // last time each verified browser was seen since launch
@Published private(set) var bridgeListening: Bool           // BridgeServer is listening on 127.0.0.1:47823
@Published var lastError: String?
var activeBlocks: [ActiveBlock] { get }
var isBlockActive: Bool { get }
var installedBrowsers: [InstalledBrowser] { get }     // supportedBrowsers that are installed
var canEmergencyExit: Bool { get }                    // block active && settings.emergencyEnabled

func startSession(modeID: UUID, minutes: Int)
@discardableResult func update(_ mutate: (inout AppState) -> Void) -> Bool   // runs Engine.validateEdit; false + lastError if rejected
func requestEmergency()                                // creates EmergencyRequest(requestedAt: now, phrase: Engine.emergencyPhrase)
func cancelEmergency()
func confirmEmergency(reason: String) -> Bool          // only if now >= requestedAt + wait; Engine.applyEmergency
func showSettings()                                    // opens SettingsView in its own NSWindow
func showEmergency()                                   // opens EmergencyView (called by the menu)
```
Every tick (1s): TrustedClock → `now`; push rules to BridgeServer when they change; `Store.writeActiveBlockMarker`;
AppBlocker sweep; save state every 60 ticks.

**AppBlocker** — observe `NSWorkspace.didLaunchApplicationNotification` + `didActivateApplicationNotification`, plus sweep each tick.
During an active block terminate (`forceTerminate()`) any running app whose bundle id is in `Engine.blockedApps`, or in
`knownBrowsers` but not in `supportedBrowsers` (overlay `BrowserWarningView` explaining why, e.g. "Safari can't be
used during a session — use Arc or Search"), or a supported browser that has been the frontmost app for 45s without a live
heartbeat for its bundle id (only while `bridgeListening`; a browser in the background is never warned about). Supported
browser without heartbeat: first show a `BrowserWarningView` ("<Browser> was disconnected from Focus. Reconnect the Focus
extension, or the browser will close in 20 s."), then after 20 s `terminate()` (graceful, tabs restore), and
`forceTerminate()` if still running 5 s later. The warning closes when the heartbeat returns. After terminating a blocked
app show `BlockedView` via OverlayController (overlays rate-limited to once per app per 10s). Never terminate Focus itself or Finder.

**BridgeServer** — Network.framework `NWListener` + `NWProtocolWebSocket`, bound to 127.0.0.1:47823 only (`.loopback`
interface). `isListening` is true on `.ready`; on failure it retries every 5s and reports changes via `onListening`. JSON text frames.
- ext → app: `{"type":"hello","ua":"…"}` (ua logged only), `{"type":"heartbeat"}`. The extension reconnects on its own
  (every 2 s) and pings the app from pages it loads (keepalive), so no other message is needed.
- Identity = the app that owns the connection. Origin and UA can't tell the browsers apart (Search, WebKit, sends a Chrome
  Origin and UA like Arc). So on `.ready`, BridgeServer reads the connection's remote port and runs
  `/usr/sbin/lsof -nP -t -iTCP@127.0.0.1:<port> -sTCP:ESTABLISHED` (off the main thread, excluding our pid) to get the client pid,
  then `responsibility_get_pid_responsible_for_pid` (private libsystem symbol, looked up with dlsym) maps it to the responsible
  app, and `NSRunningApplication(processIdentifier:)?.bundleIdentifier` gives the bundle id. Bundle ids not in
  `supportedBrowsers` keys → connection removed (logged with pid and bundle id). Messages from a connection are ignored until verified.
- Handshake `Origin` is only a cheap first filter: `chrome-extension://`, `safari-web-extension://` or `webkit-extension://`
  pass; anything else is rejected (HTTP 400).
- A connection is removed on receive error, end of stream, `isFinal`, `.waiting`, `.failed` or `.cancelled`, and on a rejected handshake.
  Bridge logs go to `os.Logger` subsystem `com.pol.focus`, category `bridge`.
- app → ext: `{"type":"rules","blockedDomains":[…],"until":"ISO8601"|null}`
  sent on hello, on every heartbeat reply, on verification, and whenever rules change.
- `lastSeen: [String: Date]` per verified bundle id: set on verification and on every message from that peer; kept after the
  connection closes. `connectedBrowsers(now:)` = bundle ids seen in the last 45s.

**OverlayController** — floating, centered, non-full-screen `NSPanel`s hosting SwiftUI (`.floating` level, `.canJoinAllSpaces`,
`.fullScreenAuxiliary`, titlebar hidden, transparent background so the view's glass shows; Esc closes a panel).
`showBlocked(target:kind:)`, `showBrowserWarning(appName:reason:deadline:)`, `showEmergency()`, `showSettings()`,
`close(_ kind: OverlayKind)` where
`enum OverlayKind: Hashable { case blocked, emergency, settings, browserWarning }`.
Each kind has at most one window. Inject `.environmentObject(app)`.

**FocusApp** — `@main struct FocusApp: App`: `MenuBarExtra { MenuContentView() } label: { lock icon }.menuBarExtraStyle(.window)`,
no Window scene: settings is an NSWindow managed by OverlayController. `NSApp.setActivationPolicy(.accessory)`; while Settings is open it is `.regular` (Dock icon, ⌘-Tab, main menu with "Settings…" ⌘, and Quit; Dock click reopens Settings), back to `.accessory` when it closes. Quit is
blocked during an active block via `applicationShouldTerminate` returning `.terminateCancel`.

## UI — `Sources/Focus/UI`, SwiftUI, macOS 26 (Liquid Glass `.glassEffect()`)
All views use `@EnvironmentObject var app: AppController`.
- **MenuContentView** (≈300pt wide): red error lines when the bridge is not listening or `lastError` is set; status module
  (`hand.raised.fill` red + "Blocking" + "<mode> · ends HH:mm" and a live countdown while blocking; `checkmark.circle` +
  "Not Blocking" + "No session or schedule is active." otherwise); one row per installed supported browser (name + dot
  "Connected" green if seen <45s ago / "Idle" gray if seen earlier since launch / "Not Connected" orange if never seen);
  "Start Session" when no block is active: mode picker, duration (presets 15m/30m/60m/2h/4h, Custom h+min, Until a clock
  time, tomorrow if already past), an orange warning per installed supported browser never seen since launch (starting is still
  allowed); "Emergency Exit…" if `app.canEmergencyExit`; "Settings…" (⌘,); "Quit Focus" (⌘Q, disabled during a block).
- **SettingsView**: tabs Modes (list; edit name, symbol, domains one-per-line, apps added via `NSOpenPanel` on /Applications
  reading `Bundle(url:)?.bundleIdentifier`), Schedules (mode, enabled, weekday toggles, start/end time), General (emergency exit:
  enabled, wait minutes, phrase length).
  All writes via `app.update { }`; if it returns false an alert shows `app.lastError`.
- **BlockedView**: "<target> is blocked" (app name for app targets), "Blocked by <Mode> until HH:mm.", countdown to the
  block end, "Back to Work" (closes the panel). No other action.
- **BrowserWarningView**: symbol + title + reason; countdown when a deadline is given; "OK" closes it.
- **EmergencyView**: step 1 explain ("This ends the current block.") + "Start"; step 2 show phrase (monospaced, not
  selectable), TextField; any jump of more than 2 characters in one change clears the field (no paste); must match exactly;
  step 3 countdown until requestedAt + wait; step 4 reason text (min 20 chars) + "Exit Block" → `app.confirmEmergency`.
- **Theme**: formatting helpers only (`timeLeft`, `clock`).
- Aesthetic: system materials and text styles, system colours, one accent, SF Symbols, subtle animations. No custom palette.

## Extension — `extension/`
Files: `manifest.json` (version `0.5.0`), `background.js`, `keepalive.js`, `blocked.html`, `blocked.css`, `blocked.js`.
- MV3. `"background": {"service_worker": "background.js", "scripts": ["background.js"]}` (scripts key = WebKit fallback).
  permissions `tabs`, `webNavigation`, `storage`; host_permissions `<all_urls>`; `web_accessible_resources` for blocked.html.
  `content_scripts`: `keepalive.js` on `<all_urls>`, `run_at` document_start, `all_frames` false.
- Must work in Chromium (Arc) and Apple WKWebExtension (the "Search" browser). Use `globalThis.browser ?? globalThis.chrome`.
- hello sends `ua: navigator.userAgent` (logged only). The app identifies the browser itself (see BridgeServer).
- WebSocket to `ws://127.0.0.1:47823`; on open send hello; heartbeat every 10s; reconnect every 2s on close. Rules go to `storage.local`.
  On every start (and every wake-up) load them and enforce them immediately while `until` is in the future, before the socket
  connects. Rules expire at `until`, not when the socket drops. Clear stored rules when the app sends empty rules
  (`until` null) or `until` has passed. Console logs connect/close (with close code) and rules applied.
- `keepalive.js` (content script) sends `{type:"ping"}` on load and every 20s while `document.visibilityState === "visible"`. The
  background answers pings and reconnects if the socket is not open. This keeps WebKit from suspending the background while the user
  browses. Every call is wrapped in try/catch (the extension context can be invalidated).
- Blocking: `webNavigation.onBeforeNavigate` (frameId 0) and `tabs.onUpdated` (url change, for SPAs) → if host matches a blocked domain
  (host == d or endsWith "." + d) redirect the tab to `blocked.html?u=<encoded original url>`. On new rules re-scan all tabs.
- blocked.html: same calm dark aesthetic as the app; shows host, live countdown to `until`. "Back to work." → message
  background `{type:"backToWork"}`; the background removes the sender tab (blocked.js falls back to `window.close()`
  when there is no tab). The app is not messaged. Poll/listen for rule changes; once host no longer blocked → `location.replace(original)`.

## Scripts
- `scripts/build.sh`: `swift build -c release --product Focus`; assemble `build/Focus.app/Contents/{MacOS/Focus,Info.plist}`
  (CFBundleIdentifier com.pol.focus, LSUIElement true, LSMinimumSystemVersion 26.0); `codesign --force --sign - build/Focus.app`.
- `scripts/install.sh`: run build; `remove_app_traces` (keeps state and history; removes the old app, LaunchAgent, preferences,
  caches, and the obsolete key files `apikey`, `apikey-gatekeeper`, `apikey-verifier`); copy to `~/Applications/Focus.app`; write
  `~/Library/LaunchAgents/com.pol.focus.plist` (RunAtLoad, KeepAlive on failure, ProcessType Interactive); bootstrap it;
  wait up to 10 s for the bridge to listen; print next steps (load the extension).
- `scripts/uninstall.sh`: refuse while `active-block-until` holds a future date unless `--force`. Otherwise: bootout agent; remove
  plist, `~/Applications/Focus.app`, the obsolete key files and the data dir; defensively remove preferences, caches, HTTPStorages,
  Saved Application State, WebKit, Application Scripts and Containers entries; `tccutil reset All com.pol.focus`. Ends with a
  leftover scan (`scan_traces`), non-zero exit if anything remains. Idempotent.
