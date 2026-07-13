---
name: analyze-app
description: Use when reviewing, auditing, or polishing app screens — "does this look right", "is this fun/understandable", "find bugs or unimplemented features on a screen", "audit the UI", or when motion/animation feels stiff, choppy, or off and evidence is needed.
---

# App Review Loop — personas, functional sweep, measured evidence

## Overview

Screen-by-screen review with three pillars, all mandatory per screen:

1. **Persona analysis** — the same evidence read through four lenses:
   designer, casual player, hardcore player (tosipelaaja), game developer.
   Checklists + report format: `references/personas.md`.
2. **Functional sweep** — every interactive element on the screen is
   exercised; dead buttons, stubs and bugs are caught, not assumed away.
3. **Measured evidence** — numbers, not vibes. Stills prove layout; **only
   video proves motion**; contrast, scale and freezes are computed.

**Iron rule: never judge animation, pacing or "feel" from a screenshot.**
A static audit of an animated screen once missed all motion problems and the
user had to report them ("tönkkö ja pätkivä"). If anything on the screen
moves, record video and run the motion profile.

## Phase 0 — Safety (before anything)

- `git status` — note uncommitted work; never revert/stash/clean it.
- **Save protection:** flows that create/advance/delete careers mutate the
  user's save. Anything destructive (New Career, multi-week advances) runs on
  a **dedicated simulator**, not the user's:
  `xcrun simctl clone <UDID> review-sim` (device must be shut down) or create
  one with `xcrun simctl create`. Verify the app's career picker never
  overwrites silently before touching the shared sim.
- **Build Debug explicitly** (`-configuration Debug`): PerfLog `PERF|` lines
  and FPS instrumentation compile to no-ops in Release — they vanish silently.

## Phase 1 — Setup

```bash
xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -configuration Debug \
  -destination 'id=<UDID>' build
xcrun simctl install <UDID> <DerivedData>/Build/Products/Debug-iphonesimulator/dynasty.app
xcrun simctl launch --console-pty <UDID> com.brewcrow.dynasty > /tmp/review/console.log 2>&1 &
```

Keep the console log for the whole session (PERF lines, AVAudio errors,
crashes). List target screens, create one task per screen (TaskCreate).

**Navigation:** no accessibility identifiers — navigate with idb taps at
*screen coordinates × 0.688*. Verify position with a fresh screenshot before
every dependent tap (never trust remembered coordinates); Coach's Board /
pause overlays freeze the play clock for stable frames.

## Phase 2 — Per-screen loop

### A. Evidence

- Screenshot(s): `xcrun simctl io <UDID> screenshot /tmp/review/<screen>_v1.png`, then Read.
- **If anything moves** (3D field, transitions, particles, tickers):
  `xcrun simctl io <UDID> recordVideo --codec h264 <file>.mp4` for 60-90 s of
  real interaction, then `python3 tools/motion_profile.py <file>.mp4`.
  Gates: no freeze ≥ 0.5 s in/near a play; bursts develop over 3-6 s; idle
  baseline level ≥ 1. Step frames (0.1-0.2 s) for animation reads.

### B. Functional sweep — find what does nothing

1. Inventory every control: from the screenshot AND the view file (buttons,
   taps, menus, context menus, swipes, toggles — code shows what the shot hides).
2. Exercise each one via idb; screenshot after each.
3. Classify: **PASS** (visible correct reaction) / **DEAD** (no reaction) /
   **STUB** (placeholder, "coming soon", empty sheet) / **BUG** (wrong
   behavior or console error). Navigate back after each detour.
4. Output a table: `control | action | result | class`. Every DEAD/STUB/BUG
   becomes a finding. Check the console log after the sweep.

### C. Persona analysis

Apply all four lenses from `references/personas.md` to the same evidence.
With Workflow orchestration, run the four personas as parallel read-only
agents over the evidence files and merge; inline, do them sequentially.
Report conflicts between personas explicitly with a proposed resolution.

### D. Findings → todos (zero tolerance)

Every finding from every persona and every sweep row becomes a TaskCreate
todo, prefixed `Fix:` (visual) / `Game:` (design) / `Bug:` / `Stub:`.
Count findings, count todos — if they differ, fill the gap immediately.
User observations get todos the moment they are said.

### E. Dispatch fixes

Background agents, one per fix batch, with: exact files, acceptance criteria,
"do NOT touch other screens", build must end BUILD SUCCEEDED. **Never two
agents on the same file concurrently.** Classify before dispatching — bug,
design gap, and perf problem need different agents and different prompts.

## Phase 3 — Verify

Rebuild → re-collect the SAME evidence (`_v2` shots, new video if motion) →
compare against v1 and against the measured gates. Motion gates re-run on
every visual change (regression check). Mark todos done or spawn follow-ups.

## Measured gates (quick reference)

| Aspect | How to measure | Band |
|---|---|---|
| Motion life | `tools/motion_profile.py` | no freeze ≥0.5 s; play 3-6 s; idle ≥1 |
| Scale | pixel-height of figure ÷ viewport (PIL crop) | vs. stated target (e.g. QB 11-14 %) |
| Contrast | ratio from screenshot pixels | ≥4.5:1 body text |
| FPS | `PERF\|` lines (Debug build) | relative: no −20 % vs. baseline run |
| Audio assets | `ffprobe` duration + volumedetect | >0 s, no clipping, no missing files |
| Balance (sim changes) | `GameSimulator.debugSimulate(50)` paired | pts ±1.5, comp% ±2, sacks ±1, TO ±0.4 |

## Common mistakes

- Judging motion from stills (the original sin — use video).
- Trusting old tap coordinates after layout changes.
- Release build silently missing instrumentation.
- Marking a screen "reviewed" without the functional sweep — pretty screens
  can be full of dead buttons.
- Only one persona: a screen that delights a designer can still starve the
  hardcore player of data, and drown the casual one.
- Fixing without classifying (bug vs design gap vs perf).
- Running New Career flows on the user's simulator/save.

## Rules

- Max 5 fix iterations per screen; 3-5 issues per batch.
- Always rebuild + re-evidence after fixes.
- Ask before game-design changes; visual fixes may dispatch without asking.
- Resumable: `TaskList` shows progress; continue where the list left off.
