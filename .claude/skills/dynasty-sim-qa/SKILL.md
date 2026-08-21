---
name: dynasty-sim-qa
description: >-
  Simulator QA playbook for Sunday Night Dynasty (com.brewcrow.dynasty) on the iPad Pro test sim.
  Use when driving the app on the simulator for verification: build/install, launch, navigate menus
  and the coached game, take screenshots, diagnose hangs, and abandon a started game cleanly.
  Prefer XcodeBuildMCP semantic UI automation (snapshot_ui + tap by element) over pixel-coordinate taps.
metadata:
  node_type: skill
  type: project
---

# Dynasty Sim QA

Playbook for driving **Sunday Night Dynasty** (`com.brewcrow.dynasty`) on the iPad simulator for
verification / visual QA. **Verified 2026-07-23** on the live app.

## VERDICT: semantic automation MOSTLY works — but it does not actuate every control

> **AMENDMENT 2026-08-21.** `snapshot-ui` remains excellent for READING the tree, and semantic `tap`
> works on most controls. It does **not** work on all of them. Verified this session: the career
> hub's **"Advance to …" button** is present in the snapshot with a ref, reports as an enabled
> button, and **swallows `ui-automation tap` silently** — 26 consecutive taps produced no state
> change and no error. An `idb ui tap` at the same location actuated it on the first try.
>
> This is the same failure shape as the `swipe` limitation documented at the bottom of this file,
> and it is dangerous in the same way: **it looks like an app bug.** A QA run this session recorded
> "the week will not advance" as a defect on two separate careers before the coordinate fallback
> disproved it.
>
> **Rule: before reporting that a control does nothing, retry it with `idb ui tap`.** A semantic tap
> that produces no state change is a tooling result, not a finding.

## Semantic automation for reading and most tapping

For years the only option was `idb` pixel taps scaled by ×0.688, because `idb ui describe-all`
returns ~1 element for this SwiftUI app. **That limitation does not apply to XcodeBuildMCP.**
Its `ui-automation snapshot-ui` uses a different mechanism (AXe/XCUITest-based `rs/1` runtime
snapshot) and exposes the **full SwiftUI accessibility tree**.

Evidence from the 2026-07-23 run (dashboard → Coach the Game → play select → abandon), zero
coordinate math:

| Screen | `snapshot-ui` result |
|---|---|
| Career dashboard | 449 elements, 53 tap targets — every card by label: `Continue Career`, `Coach the Game`, `Advance to Week 2`, `Roster`, `Salary Cap, Used, $-24.8M …` |
| In-game coaching | targets for `Snap the ball — run Inside Run` (SNAP), `Reverse the play to the opposite side` (REVERSE), `AUDIBLE · 2`, the 5 play cards (`Toss Sweep. Pitch wide and win with speed.` …), route tabs `Run/Short/Medium/Deep/Special`, `Leave the game` (the X), `Sim to Final & Leave`, `Call timeout, 3 remaining` |
| Abandon dialog | `Leave the game?`, `Sim to Final & Leave`, `Abandon Game` |

**The entire task flow was driven by tapping elements by label — no `idb`, no ×0.688.** The
coordinate table below is kept only as a last-resort fallback (see "When you still need coordinates").

Everything in this file was **run successfully** this session unless a step is explicitly marked
`[NOT RE-RUN THIS SESSION]`.

---

## Environment

- **Sim UDID:** `049C7295-7294-48E8-8B6B-D31CE41E4353` (iPad Pro 13-inch M5). Screen `2064×2752` px.
- **App bundle id:** `com.brewcrow.dynasty`
- **Xcode project:** `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty.xcodeproj`, **scheme `dynasty`** (only scheme).
- **CLI:** invoked as `npx -y xcodebuildmcp@latest <group> <command>`. Discover with
  `npx -y xcodebuildmcp@latest tools` and `... <group> <command> --help`.

Convenience for one-off shells (bash state does NOT persist between agent tool calls — set it in
every command block):
```bash
UDID=049C7295-7294-48E8-8B6B-D31CE41E4353
```

Check the sim is booted and the app is running:
```bash
xcrun simctl list devices | grep 049C7295              # → "(Booted)"
xcrun simctl spawn $UDID launchctl list | grep dynasty # → UIKitApplication:com.brewcrow.dynasty[...]
```

---

## Build & install

The test sim already has the latest build installed. When you do need to rebuild:

`[NOT RE-RUN THIS SESSION — canonical form emitted by the CLI's list-schemes; verify on first use]`
```bash
# Build, install, and launch on the sim in one step (preferred for run intent):
npx -y xcodebuildmcp@latest simulator build-and-run \
  --project-path /Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty.xcodeproj \
  --scheme dynasty --simulator-id 049C7295-7294-48E8-8B6B-D31CE41E4353

# Compile-only (no launch):
npx -y xcodebuildmcp@latest simulator build \
  --project-path /Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty.xcodeproj \
  --scheme dynasty --simulator-id 049C7295-7294-48E8-8B6B-D31CE41E4353
```

Raw `xcodebuild` fallback (from project memory, `[NOT RE-RUN THIS SESSION]`):
```bash
xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty \
  -destination 'id=049C7295-7294-48E8-8B6B-D31CE41E4353'
```

**VERIFIED** helpers:
```bash
# List schemes (confirms project wiring; scheme = "dynasty"):
npx -y xcodebuildmcp@latest project-discovery list-schemes \
  --project-path /Users/jtvaris/workspace/jtvaris/IOS/Dynasty/dynasty/dynasty.xcodeproj
```

---

## Launch (VERIFIED)

```bash
npx -y xcodebuildmcp@latest simulator launch-app --simulator-id $UDID --bundle-id com.brewcrow.dynasty
```

⚠️ **Gotcha:** on an already-running app this does a **fresh cold launch** — it resets the app to
the **main menu** (it does NOT just foreground the current screen). Observed 2026-07-23: after this
call the app dropped from the in-game/dashboard state back to the "SUNDAY NIGHT DYNASTY" main menu
with a `Continue Career` button (`CONTINUE: BUFFALO BILLS · WEEK 1, 2029 SEASON`). Use it to reset to
a known start; don't use it to "wake" a screen you want preserved.

---

## Semantic navigation — the core loop (VERIFIED)

Three primitives:
- `ui-automation snapshot-ui --simulator-id <UDID>` — dumps `ref|action|role|label|value|id` for every target.
- `ui-automation tap --simulator-id <UDID> --element-ref <ref>` — taps one ref from the latest snapshot.
- `ui-automation wait-for-ui ... --predicate textContains --text "..."` — poll+settle, returns matching rows.

### Critical state gotcha
`snapshot-ui`/`tap` are **stateful**: the snapshot is cached **on disk keyed by simulator with a short
TTL**. Each `npx` call is a fresh process, so a `tap` in a *later, separate* agent tool-call fails with
`SNAPSHOT_MISSING`. **Fix: snapshot and tap in the SAME shell command block** (sequential `npx` calls
in one Bash invocation share the on-disk cache). A persistent `daemon` also exists
(`npx -y xcodebuildmcp@latest daemon start|status|stop`) but is not needed if you follow the pattern below.

### Robust recipe: resolve ref by label, then tap (VERIFIED)
Refs like `e183` were stable across snapshots this session, but do **not** hardcode them — resolve
fresh from the label each time, in one block:
```bash
UDID=049C7295-7294-48E8-8B6B-D31CE41E4353
SNAP=$(npx -y xcodebuildmcp@latest ui-automation snapshot-ui --simulator-id $UDID 2>/dev/null)
REF=$(echo "$SNAP" | grep -i "Toss Sweep" | head -1 | awk -F'|' '{print $1}' | tr -d ' ')
npx -y xcodebuildmcp@latest ui-automation tap --simulator-id $UDID --element-ref "$REF"
```
After a tap the CLI often warns *"refreshed runtime snapshot did not settle before timeout"* — this
is benign; just re-snapshot before the next tap (the recipe already does).

⚠️ **The snapshot returns the WHOLE navigation stack, including off-screen/covered screens.** In-game,
the dashboard's and main menu's buttons (`Continue Career`, `Coach the Game`, …) still appear in the
list. So: match on a **specific, unique** label (`"Toss Sweep"`, `"Abandon Game"`, `"Leave the game"`),
`head -1`, and prefer labels that only exist on the current screen. Newly-pushed screens get the
highest `eNNNN` refs (e.g. in-game targets were `e2483`–`e2586`).

### Wait for a screen to be ready (VERIFIED)
```bash
npx -y xcodebuildmcp@latest ui-automation wait-for-ui --simulator-id $UDID \
  --predicate textContains --text "Coach the Game" --timeout-ms 4000
```
Predicates: `exists|gone|enabled|focused|textContains|settled`; selectors: `--element-ref|--identifier|--label|--role|--value`.

---

## Verified label map (2026-07-23 build)

Tap these by label with the recipe above. (Refs shown are illustrative from this session; re-resolve.)

**Main menu:** `Continue Career`, `New Career`, `How to Play`, `Settings`.

**Career dashboard:** `Coach the Game`, `Game Plan`, `Advance to Week 2`, `Depth Chart`,
`Development`, `Injuries`, `Roster`, `Staff`, `Schedule`, `Standings`, `Draft`, `Scouting`, `Cap`,
`Quit to main menu`. Cards carry rich labels (`Salary Cap, Used, $-24.8M, -7% …`).

**In-game coaching screen:**
| Intent | Label to match |
|---|---|
| SNAP | `Snap the ball` (full: `Snap the ball — run <PlayName>`) |
| REVERSE | `Reverse the play to the opposite side` |
| AUDIBLE | `AUDIBLE · 2` |
| Route tabs | `Run`, `Short`, `Medium`, `Deep`, `Special` |
| Play cards (Run tab) | `Inside Run`, `Outside Run`, `Counter`, `Toss Sweep`, `Draw` (full labels append a description, e.g. `Toss Sweep. Pitch wide and win with speed.`) |
| Exit (the X) | `Leave the game` (role button, id `xmark`) |
| Timeout | `Call timeout, 3 remaining` |
| Manage / Stats / Sim | `Manage players — open the Coach's Board`, `Game stats — open the live box score`, `Simulate the rest of the game` |

**"Leave the game?" dialog:** `Sim to Final & Leave`, `Abandon Game`.

Selecting a play card flips the selection (gold border + ✓) and updates the SNAP label to that play —
verified by tapping `Toss Sweep` and screenshotting.

---

## Screenshots (VERIFIED)

Save to a known path (most predictable — use this for evidence dirs):
```bash
xcrun simctl io $UDID screenshot /path/to/shot.png
```
Native XcodeBuildMCP screenshot also works (`✅ Screenshot captured`), returns a path/base64:
```bash
npx -y xcodebuildmcp@latest ui-automation screenshot --simulator-id $UDID --return-format path
```
Convention: keep run screenshots in a scratch dir (`stateN_<what>.png`) and `Read` them to
eyeball-verify UI state after each meaningful tap. Screenshots are `2064×2752` px; Claude displays
them at `1500×2000`.

---

## Play-clock setting (READ ONLY — do not flip without intent)

The test sim intentionally has the play clock **OFF** so taps don't race the clock. Confirmed
2026-07-23: `playClockSetting = off`.
```bash
xcrun simctl spawn $UDID defaults read com.brewcrow.dynasty playClockSetting   # → off
```
**To restore normal play (10s clock)** when you're done making the sim test-friendly:
```bash
xcrun simctl spawn $UDID defaults write com.brewcrow.dynasty playClockSetting -string 10
```
Leave it OFF while doing tap-driven QA; restore to `10` before handing the sim back for real play.

---

## Abandon-game exit ritual (VERIFIED — keeps the week playable)

Starting + abandoning a coached game does **not** consume the week (the dialog states
*"nothing is saved"*, and afterwards the dashboard still offers `Coach the Game` / `Advance to Week 2`).
Always end a coached-game test with this so the week stays playable:
```bash
UDID=049C7295-7294-48E8-8B6B-D31CE41E4353
# 1) Tap the X ("Leave the game")
SNAP=$(npx -y xcodebuildmcp@latest ui-automation snapshot-ui --simulator-id $UDID 2>/dev/null)
REF=$(echo "$SNAP" | grep -i "Leave the game" | head -1 | awk -F'|' '{print $1}' | tr -d ' ')
npx -y xcodebuildmcp@latest ui-automation tap --simulator-id $UDID --element-ref "$REF"
sleep 1
# 2) Confirm "Abandon Game"
SNAP=$(npx -y xcodebuildmcp@latest ui-automation snapshot-ui --simulator-id $UDID 2>/dev/null)
REF=$(echo "$SNAP" | grep -i "Abandon Game" | head -1 | awk -F'|' '{print $1}' | tr -d ' ')
npx -y xcodebuildmcp@latest ui-automation tap --simulator-id $UDID --element-ref "$REF"
```
Verify you're back at the dashboard (`Coach the Game` present, `Snap the ball` gone). To finish at a
clean known state, `launch-app` returns to the main menu (which shows `CONTINUE: … WEEK 1`, proving
the save is intact).

---

## Hang diagnosis (from project memory)

When the app stops responding to taps:
```bash
ps aux | grep '[d]ynasty.app'          # look for a process pinned at ~100% CPU
sample <pid> 5 -file /tmp/dynasty_sample.txt   # 5s symbolicated call graph → names the Swift file:line
```
Known disease pattern: engine loops reading SwiftData `@Model` properties on the main thread
(GameSimulator / FA-complete / old debug-skip paths). Also: taps race modal animations — after a
tap that opens/dismisses a sheet, wait ~1s and re-snapshot (or use `wait-for-ui`) before the next tap.

---

## When you still need coordinates (fallback only)

⚠️ **RUNNER INTERFERENCE (2026-08-07):** the XCUITest runtime behind `snapshot-ui` has been seen
DRIVING the app on its own — unrequested navigations and a rotation to landscape mid-run. If the
app starts moving without your taps, abandon the semantic session and drive the whole run with
`idb ui tap` coordinates instead (that is how the #162 verification was completed).

⚠️ **SCROLLING: XcodeBuildMCP `swipe` and `gesture` presets silently FAIL on this app's SwiftUI
Lists** (verified 2026-08-06 on PlayerDetailView: 6 swipes + 4 gesture presets moved nothing, no
error reported — a QA run falsely concluded the card's Actions section didn't exist because it
never actually scrolled). **Scroll with `idb ui swipe` coordinates instead**, e.g. full-page down:
```bash
idb ui swipe --udid <UDID> 516 1000 516 300 --duration 0.3
```
After an intended scroll, ALWAYS confirm content moved (screenshot or AX diff) before concluding
anything about what a screen does or doesn't contain.

Semantic taps covered **100%** of the tested flow, so this should be rare — needed only if a control
has no accessibility label, or `snapshot-ui` is unavailable. XcodeBuildMCP's `tap` takes **only**
`--element-ref` (no x/y); its `gesture` command is preset scroll/swipe only. So coordinate taps mean
falling back to **`idb`**:
```bash
idb ui tap --udid 049C7295-7294-48E8-8B6B-D31CE41E4353 <x> <y>
```
**The ×0.688 math (explained once):** a Claude-displayed screenshot is `1500×2000`. idb works in
device points = displayed × **0.688** ( = original px ÷ 2; `1032×1376` point space; `1032/1500 = 0.688`).
So: read the pixel off the `1500×2000` displayed screenshot, multiply by `0.688`, tap.

Known idb-point fallbacks (only valid for the 2026-07 layout; **verify from a screenshot first**):

| Target | idb point (x,y) |
|---|---|
| Main-menu Continue Career | 516, 1049 |
| Dashboard Coach the Game | 465, 290 |
| In-game Run tab | 111, 1077 |
| In-game Toss Sweep card | 718, 1163 |
| In-game X (Leave the game) | 1005, 25 |
| Abandon Game (dialog) | 516, 752 |
| Back button | 32, 117 |

---

## Optional Swift-side hardening (TODO for the user — NOT applied here)

Semantic automation **already works today** off the app's existing accessibility *labels*, so this is
polish, not a blocker. Adding stable `.accessibilityIdentifier`s would make scripts more durable:

- **Play cards** are matched by descriptive text (`"Toss Sweep. Pitch wide and win with speed."`).
  A stable id (e.g. `playcard.tossSweep`) would survive copy changes — the card subtitle is the kind
  of string that gets reworded.
- **SNAP** label embeds the current play (`"Snap the ball — run Inside Run"`); a fixed
  `ingame.snap` id would let scripts match `--identifier ingame.snap` regardless of selected play.
- **Screen scoping:** the AX snapshot returns the whole nav stack, so main-menu/dashboard buttons
  co-exist with in-game ones. Per-screen identifiers (`mainmenu.continueCareer`, `dashboard.coachGame`,
  `ingame.reverse`, `ingame.leave`, `dialog.abandon`) would remove any ambiguity from label matching.
- **Route tabs** (`Run/Short/Medium/Deep/Special`) and dashboard nav (`Roster/Staff/…`) — short,
  potentially reused words; scoped ids would disambiguate.

These are enhancements to file as a ticket; do not add them as a side effect of a QA run.
