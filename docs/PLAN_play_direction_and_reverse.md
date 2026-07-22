# Plan: play-direction mirror fix + REVERSE button / either-side runs

Two related follow-ups from the 2026-07-22 animation session, investigated and ready to
implement. They are **orthogonal** and can land in either order, but read §3 of Plan B for
how they compose (do NOT double-negate the lateral).

Both are **presentation-only** — the engine/sim is entirely side-agnostic (direction is
never read by `PlaySimulator`/`LiveGameEngine`), so **no engine or Codable changes** in either.

---

## PLAN A — Fix the field↔card left/right MIRROR

### Diagnosis (traced, not assumed)
The 3D field and the playbook card disagree on left/right for **every** offensive play (runs
make it obvious; passes mirror too). Root cause is a **world→screen handedness mismatch**, NOT
the `RouteSpec.resolve` lateral:

- World contract: X = sideline↔sideline, Z = endzone↔endzone. Offense drives **+Z when home**,
  **−Z when away** (`direction = offenseIsHome ? +1 : -1`).
- `RouteSpec.resolve` (`RouteSpec.swift:58-68`) makes **world X direction-INDEPENDENT**
  (`startX + lateral*sideSign`; only Z uses `direction`). Formation X and **defense X** are
  likewise direction-independent (`offensePositions` `PlayChoreographer.swift:269-282`,
  `defensePositions` `:367-380`). ⇒ On the field, **offense and defense already line up
  correctly** in world space. The field is internally valid; only its comparison to the card is off.
- The **card** (`RouteSpec.diagram` `:360-364`, `PlayDiagramView.swift:20-21`) is drawn with
  fixed handedness: world **+X → screen RIGHT**.
- The **camera** flips screen handedness with `viewFacing` (`FootballFieldScene.focusCamera`
  `:1189-1190`): `viewFacing == -1` → looks −Z → +X = screen RIGHT; `viewFacing == +1` →
  looks +Z → **+X = screen LEFT** (verified via gluLookAt: camera-right = world −X).
- `viewFacing` is set from the USER's team, fixed all game (`CoachedGameView.swift:2822`,
  `setViewFacing(playerTeamIsHome ? 1 : -1)`). The card is only shown when the user is on offense.

**Truth table (screen side of a route whose resolved world X is +):**

| User on offense | viewFacing | Field +X→ | Card +X→ | Result |
|---|---|---|---|---|
| **Home** offense (drives +Z) | **+1** | LEFT | RIGHT | **MIRROR** |
| Away offense (drives −Z) | −1 | RIGHT | RIGHT | MATCH |

So the mirror hits the **HOME-coached** user (opposite of the earlier "away" guess — the
observer likely coached home and called it "away framing"). The mechanism (viewFacing flips
L/R, lateral doesn't) is right; it's a **camera/viewFacing** effect, not a `direction` effect —
which is exactly why keying the fix to `direction` is wrong.

### Recommended fix — Option B: mirror all world-X at the scene data-in boundary
Mirror the **entire** rendered world in X by one sign keyed on `viewFacing`, so offense +
defense + ball + routes all mirror **together** (stay mutually consistent) and the field's
handedness is forced to equal the card's. Touches **only `FootballFieldScene.swift`**; the
choreographer stays a pure function and the card stays the source of truth.

Rejected: **Option A** (`resolve` lateral `* direction`) — fixes the wrong case AND desyncs the
carrier from his blockers/defense (only the route flips). **Option C** (camera keeps +X
screen-right) — can't flip only handedness without breaking endzone/yard text, normals, or the
"behind your unit" framing.

**Sign:** `lateralSign = -viewFacing` (home +1 → −1 mirror; away −1 → +1 no-op). **VERIFY the
sign empirically first (§ test), it's the #1 risk.**

**Edits (all `FootballFieldScene.swift`):**
1. Add `private(set) var lateralSign: Float = -1`; in `setViewFacing` (`:1084`) set
   `lateralSign = -viewFacing`.
2. `positionPlayers` `:596` & `:606`: `info.x → info.x * lateralSign`.
3. `movePlayersToFormation` `:873`: `info.x → info.x * lateralSign`.
4. `huddle` `:943`/`:950`: mirror `spot.x` (shadow `let sx = spot.x * lateralSign`, use it in
   both the move target AND the `atan2(centerX - sx, …)` turn-in yaw; compute `centerX` from the
   mirrored X too).
5. `execute(step:)` moves `:3082`/`:3086`: `let to = SCNVector3(move.to.x * lateralSign, move.to.y, move.to.z)` and use `to`.
6. `execute(step:)` paths `:3095`/`:3099`: `let pts = path.points.map { SCNVector3($0.x * lateralSign, $0.y, $0.z) }`, use `pts`.
7. `execute(step:)` ball `:3197`/`:3200`: mirror `to.x` in `.arc` and `.slide`.

**Do NOT** mirror inside `run(node:to:)` (`:1887`) — it's also called with read-back node-space
coords (post-play drift/followThrough/postPlayWalk) → double-negation. Mirror once at the
logical→scene boundary. Camera/referee/markers are at x=0 (untouched). Optional: sideline
review cam x=-27.5 (`:1467`) → `* lateralSign` to keep the review angle stable.

### Verification
1. **Sign test FIRST** — coach a **HOME** team, call Toss Sweep on offense, watch RB vs the
   card's gold arrow. If RB sweeps the OPPOSITE side (prediction) → `-viewFacing` is right; if it
   already matches → use `+viewFacing`. Re-run, confirm RB now matches the arrow.
2. **Home drive:** Toss Sweep, Outside Run, a pass (Slant/Quick Out) → all break to the card
   side; OL/WR formation matches the card; defense still lines up across the correct men.
3. **Away drive:** repeat everything coaching the AWAY team — must ALSO match (was correct
   before; confirm not inverted).
4. **Possession stability:** after a change of possession the user's own team keeps a stable
   screen L/R (guards against keying to `direction`).
5. **Asymmetric spot-checks (both framings):** Counter (cutback side), Jet Sweep (motion +
   sweep direction), WR Screen, Cross/Flood/Post; confirm **ball flight** lands on the correct
   side (tests edit 7).

### Risks
Sign error (#1 — do the sign test). Missing any funnel (2-7) → that element mirrors out of step
(grep for other places building a world `SCNVector3` from choreographer data). Don't mirror
read-back positions. Card stays fixed (never flip it per home/away). Camera/text untouched by
design (all at x=0). Pre-snap yaw uses average Z not X → who-faces-whom unaffected.

---

## PLAN B — REVERSE button + run-to-either-side

### Approach
Sim is 100% side-agnostic (`OffensivePlayCall.simulatorHint` carries only scalars;
`PlaySimulator`/`GameSimulator` use `direction` for momentum sign only). So this is a pure
geometry reflection. **Recommend Option B: a `mirror: Float` (±1) flag + a REVERSE button**,
threaded through the shared geometry pipeline (`RouteSpec` → `PlayChoreographer` →
`PlayDiagramView`). The enum, Codable rawValues, AI recommender, schemes, and audibles are
untouched. (Reject Option A "separate L/R enum cases" — doubles cards + forces edits to every
switch over the enum + save-file migration, for identical sim distributions.)

### Composition with Plan A (do NOT double-negate)
Keep three separate multiplicative factors on the lateral term:
```
worldLateral = waypoint.lateral * sideSign * mirror * screenSign
worldDepth   = direction * waypoint.depth
```
- `mirror` (±1) = the coach's flip — **offense-relative**, applied in spec/offense space (this plan).
- `screenSign` = Plan A's `lateralSign`, home/away **screen mapping**, applied at the scene boundary.
- The card always resolves with `direction:1`/`screenSign +1`, so the card reflects with `mirror`
  alone; the field reflects with `mirror` AND gets `screenSign` from Plan A → card and field agree
  for both home and away. Do NOT fold `mirror` into `sideSign` or `direction`.

**Subtlety:** `sideSign = startX < -0.5` is a coarse threshold, so flipping only the alignment X
does NOT flip routes for **centered** carriers (RB at x=0 on insideRun/dive, QB on qbSneak/draw).
The robust primitive applies `mirror` to the **lateral displacement** in `resolve` (not by editing
the spec table, not by alignment-flip alone), computing `sideSign` from the pre-reflection X:
```swift
// resolve(..., mirror: Float = 1)   // startX already reflected by offensePositions
let canonicalStartX = startX * mirror
let sideSign: Float = canonicalStartX < -0.5 ? -1 : 1
for wp in waypoints {
    let lateral = wp.lateral * sideSign * mirror
    points.append((startX + lateral, losZ + direction * wp.depth * depthScale))
}
```
`mirror == 1` is byte-for-byte today's behavior (safe no-op default).

### Edits
**Geometry — `RouteSpec.swift`:** add `mirror: Float = 1` to `resolve` (`:58`, apply as above),
`points` (`:73`, forward), `diagram(for:mirror:)` (`:351`, pass into `offensePositions` and
`spec.points` so the card art flips). Spec table stays canonical/unchanged.

**Alignment/choreo — `PlayChoreographer.swift`:** `offensePositions` (`:230`) add `mirror`,
reflect final X: `raw.map { (clampX($0.x * mirror), clampZ($0.z), $0.number) }` (`:282`) — flips
rb/slot/teX, swaps WR-L/R; QB/OL (x=0) unaffected. `formation` (`:136`), `preSnapStep` (`:197`),
`steps` (`:388`) add `mirror` and forward. `Context` (`:443`/`:478`) add `let mirror`, pass at
`:489`. `specPath` (`:825`) / `fallbackPath` (`:841`) pass `mirror: c.mirror`.

**Card — `PlayDiagramView.swift:12`:** add `var mirrored = false` → `RouteSpec.diagram(for:mirror: mirrored ? -1 : 1)`.

**UI — `CoachedGameView.swift`:** `@State mirrored = false`; `var offMirror: Float { mirrored ? -1 : 1 }`.
- REVERSE button in the snap bar next to AUDIBLE (template `:1354-1371`), for the selected run
  (generalizes to asymmetric passes later). Action: `withAnimation { mirrored.toggle() }; previewFormation()`.
- Reset on new selection: in `.onChange(of: selectedCall)` (`:403`) set `mirrored = false` first;
  also at `selectedCall = nil` (`:3215`).
- Selected card reflects side: `playCard` `:1486` → `PlayDiagramView(call: play, mirrored: play == selectedCall && mirrored)`.
- Preview: `syncFieldToSituation` (`:3482`) pass `mirror: engine.playerIsOnOffense ? offMirror : 1` into `formation`.
- Snap: `snap`→`runPlay` carry `offMirror` into `preSnapStep` (`:3221`) and `steps` (`:3280`);
  opponent's snap uses `mirror = 1`. Replays are auto-safe (recordPlay stores resolved geometry).

**Engine: no changes.**

### Minimal first slice (ships the feature)
resolve/points/offensePositions gain `mirror` (no-op default) → diagram+PlayDiagramView `mirrored`
→ Context/steps/formation/preSnapStep thread it → CoachedGameView state + REVERSE button +
reset-on-change + pass into preview/card/snap. No engine/enum/Codable edits.

### Verification
1. **Unit:** `diagram(for:.toss, mirror:-1)` == `diagram(for:.toss, mirror:1)` reflected across
   `x=0.5` (points AND alignment dots); repeat for a centered carrier (insideRun/dive) — proves the
   sideSign subtlety flips (key regression guard).
2. **Home field:** Toss Sweep + REVERSE + snap → RB sweeps the opposite sideline AND the selected
   card shows flipped art matching the field.
3. **Away field:** same coaching the away team; run AFTER Plan A lands, confirm mirror + screenSign
   compose (no double-negation).
4. **No-op guard:** `mirror=1` everywhere → geometry byte-identical (snapshot a few `steps`/`diagram` outputs).
5. **Interaction:** new card / audible resets `mirrored`; opponent snaps never mirrored; replay of a
   flipped play re-stages flipped.

---

## Key files (both plans)
- `dynasty/dynasty/UI/Match/RouteSpec.swift` — `resolve` `:58`, `points` `:73`, `diagram` `:351`
- `dynasty/dynasty/UI/Match/PlayChoreographer.swift` — `offensePositions` `:230`, `defensePositions` `:367`, `formation` `:136`, `preSnapStep` `:197`, `Context` `:478`, `steps` `:388`, `specPath` `:825`
- `dynasty/dynasty/UI/Match/FootballFieldScene.swift` — `viewFacing`/`setViewFacing` `:1082`, `positionPlayers` `:577`, `movePlayersToFormation` `:848`, `huddle` `:939`, `execute(step:)` `:3071`, `focusCamera` `:1164`
- `dynasty/dynasty/UI/Match/PlayDiagramView.swift` — `:12`
- `dynasty/dynasty/UI/Match/CoachedGameView.swift` — `setViewFacing` `:2822`, `.onChange(selectedCall)` `:403`, snap bar `:1353`, `playCard` `:1486`, `syncFieldToSituation` `:3480`, `snap`/`runPlay` `:3023`/`:3133`
- `dynasty/dynasty/Domain/Enums/PlayCall.swift` — `OffensivePlayCall` `:12` (no change under Plan B Option B)
- Engine (`dynasty/dynasty/Engine/**`) — **no changes** in either plan
</content>
</invoke>
