# Focus — design contract

Two worlds, never mixed:
- **Native macOS surfaces** (menu bar popover, Settings window, overlay panels) → **pure Apple**. Follow the macOS 26
  Human Interface Guidelines: system materials and Liquid Glass, SF Pro at system text styles, SF Symbols, standard
  controls, system colours, Apple copy conventions. It should look like something Apple shipped (Control Center,
  Screen Time, Clock). **No hundred. branding here** — no lowercase-with-periods voice, no custom heavy headlines,
  no wordmark, no custom palette.
- **Non-Apple surfaces** (the browser block page `extension/blocked.*`) → full **hundred.** branding (see bottom).

Every block is a plain block. There are no strictness levels, no access requests and no AI.

## Native — rules

**Materials & glass**
- The MenuBarExtra `.window` already provides the system glass background. Do NOT add a background, colour scheme
  override or extra glass behind the whole popover. Never put glass on glass.
- Group content like Control Center modules: `RoundedRectangle(cornerRadius: 12)` filled with `.fill.quaternary`
  (or `.background(.fill.quaternary, in: .rect(cornerRadius: 12))`), 12pt padding, 10–12pt spacing between groups.
- Liquid Glass only where Apple uses it: the floating overlay panels themselves (`.glassEffect(.regular, in: .rect(cornerRadius: 26))`
  as the panel surface) and buttons (`.buttonStyle(.glass)` / `.glassProminent`). Follow system light/dark — no forced dark.

**Typography** — system text styles only, no custom tracking:
`.title2.weight(.semibold)` panel titles · `.headline` group titles / status title · `.body` · `.subheadline` +
`.foregroundStyle(.secondary)` for supporting text · `.caption` + `.tertiary` for fine print. Timers:
`.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()` with `.contentTransition(.numericText())`
(like the Clock app); small timers `.body.monospacedDigit()`.

**Colour** — system semantics only: `.primary/.secondary/.tertiary`, `.tint` = the user's **macOS accent colour**
(don't set a custom tint), `.green` connected/success, `.orange` warning/not connected, `.red` blocking/denied/failed,
`.secondary` idle. Status dots 8pt circles. SF Symbols with `.symbolRenderingMode(.hierarchical)`.

**Controls** — standard: `Picker` (`.menu` style for mode and duration), `Stepper`,
`TextField`/`TextEditor` with `.textFieldStyle(.roundedBorder)` or Form rows, `Toggle`, `DatePicker`.
Primary action `.buttonStyle(.glassProminent)` + `.controlSize(.large)` + `.keyboardShortcut(.defaultAction)`;
secondary `.buttonStyle(.glass)`; cancel gets `.keyboardShortcut(.cancelAction)`.

**Copy (Apple voice)** — sentence case for labels and messages, title case for buttons and menu items, no trailing
periods on titles/buttons, ellipsis for actions that open a window: "Not Blocking"/"Blocking" status title,
"Start Session", "Settings…", "Quit Focus", "Back to Work", "Exit Block". Messages: "YouTube is blocked until 11:45.",
"This ends the current block."

**Menu popover (~300pt wide, 14pt outer padding)**
1. Status module: large SF Symbol in a 36pt circle (`hand.raised.fill` red while blocking, `checkmark.circle` secondary when not
   blocking) + "Blocking"/"Not Blocking" (`.headline`) + one `.subheadline .secondary` line (mode · ends 11:45, or
   "No session or schedule is active."). While blocking: the big rounded timer below.
2. Browsers module: rows "Arc" / "Search" (drop ".app"), right side 8pt dot + `.secondary` text "Connected"/"Idle"/"Not Connected".
3. Start module (when not blocking): `Picker("Mode", …).pickerStyle(.menu)`, duration chips (15m, 30m, 1h, 2h, 4h, Custom, Until),
   full-width "Start Session" (glassProminent, large); warnings as `.caption` orange with
   `exclamationmark.triangle.fill`.
4. Footer: `Divider()`, then menu-style rows — "Emergency Exit…" (only while a block can be ended), "Settings…" (⌘,),
   "Quit Focus" (⌘Q, disabled during a block) — plain buttons, full-width, left-aligned, hover highlight like a native menu.

**Overlay panels (Blocked / Emergency / BrowserWarning)** — like a macOS 26 alert/sheet:
width 440, padding 24, the panel surface is Liquid Glass (radius 26). Top: 56pt SF Symbol (hierarchical, coloured by
state) → `.title2.semibold` title (sentence case: "youtube.com is blocked") → `.subheadline .secondary` explanation →
content (Form-like rows, rounded-border fields, labels above fields in `.subheadline .secondary`) → buttons row
right-aligned (secondary then primary), or full-width stacked when there are only two short actions. Big rounded timer
where relevant.

**Settings window** — standard macOS settings: `TabView` with tabs Modes (`square.stack`), Schedules (`calendar`),
General (`gearshape`); each a `Form` with `.formStyle(.grouped)`;
native rows, `LabeledContent`, `Section` headers in sentence case. Window ~620×520.

**Theme.swift** — keep it tiny: only formatting helpers (`timeLeft`, `clock`). No custom colour palette for native UI.

## Web — hundred. branding (`extension/blocked.*`, already implemented — keep)
Pure black, bold Helvetica Neue, lowercase with periods, `focus.` wordmark, `blocked.` headline, glass card, white pill
`back to work.`; the keyboard focus ring uses the ink colour. Fixed palette, not set by the app. Tokens: ground #000/#fff,
ink #fff/#0a0a0a, card #0c0c0e, dim #98989e, faint #5a5a60, hairline #232326.
