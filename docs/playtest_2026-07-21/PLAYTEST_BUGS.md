# Playtest bugs — handoff (2026-07-21)

Session ended here deliberately; fix these in a fresh session. All animation work
below is **built + launches clean but UNCOMMITTED** (user commits). `git status` shows
~25 changed/new files (SkeletalFigure.swift, FootballFieldScene.swift, PlayChoreographer.swift,
Resources/PlayerClip_*.usdc, tools/asset-pipeline/*, TODO.md).

## Video references (persistent)
Recordings: `~/Documents/Snagit/2026-07-21_09-22-52.mp4` and `..._09-23-25.mp4`.
Frame-grids saved here in the repo:
- `rec_0922_toss-sweep_run+tackle.png` — **TOSS SWEEP run** (2nd&4). RB Damien Johnson rushes 7yd, tackled. Watch for #10 (tackle ground-clip), #9-teleport, #7 (facing).
- `rec_0923_deep-pass_dropback+throw+catch.png` — **deep pass "BOMB"** (2nd&17). QB dropback → throw → 30yd catch. Watch for #9 (throw-late, QB ball-in-hand, teleport, tackle-after-catch), #7 (facing).
- `diag_figure-faces+Z_front-vs-side.png` — proof the skeletal figure faces **+Z** correctly (front camera = front, side camera = profile).

---

## #7 — Pre-snap facing: players turned LEFT
**User:** all offensive linemen + all players appear turned LEFT in the pre-snap stance.
Should be: linemen facing the defense (left side→left, right side→right, center→center),
WR/TE/QB/RB facing center/downfield.

**Investigation (done):**
- Skeletal figure faces **+Z** at yaw=0 — verified by rendering idle from pure front (+Z, camera sees the front/number) and pure side (+X, sees profile). See `diag_figure-faces+Z_front-vs-side.png`. Crouch frame (idleFraction) also faces +Z (no rotation).
- Spawn facing: `FootballFieldScene.swift:584-608` — `homeYaw = awayAvgZ >= homeAvgZ ? 0 : .pi`, every node `eulerAngles=(0,homeYaw,0)`. Settle: `840-889` (`movePlayersToFormation`, `settleYaw`). Both set all players to face across the LOS. **Correct in isolation.**

**Still to do:** pinpoint the exact wrong player/orientation IN the recording (facing is code-correct, so it's likely a camera-relative read, OR the light crouch stance `idleFraction` capped at 0.17 in `SkeletalFigure.swift:189` reads as "standing turned" not a 3-point stance, OR a specific role's stance clip). Look at the pre-snap frames (row 1) of both grids.

## #8 — "Go for 2" asked from the DEFENSE
**User:** the 2-pt conversion decision was offered while the player was on defense (opponent scored). "Really weird."

**Investigation (done):**
- View gate: `CoachedGameView.swift:2929-2943` — shows the XP/2pt panel only if `engine.playerAttemptsConversion`.
- Engine: `LiveGameEngine.swift:3204` `playerAttemptsConversion = pendingConversion?.scoringTeamIsHome == playerTeamIsHome`. Set in `finishOrHoldDrive` (`3277-3289`): `pendingConversion = PendingConversion(scoringTeamIsHome: homeHasPossession)`. **Correct for a normal offensive TD** (possession == scorer; possession isn't flipped yet here).

**Hypothesis / to do:** a **DEFENSIVE or RETURN touchdown** (pick-six, fumble-return, kick/punt-return TD). For those the scoring team ≠ `homeHasPossession` (offensive possession), so `scoringTeamIsHome` inverts → `playerAttemptsConversion` inverts → the coach whose offense was on the field gets the prompt for the OPPONENT's return TD. Also `bookPoints(forHome: homeHasPossession)` at `3282` would credit the wrong team on such TDs. **Confirm the TD type that triggered it**, then thread the true scoring team (not offensive possession) into `finishOrHoldDrive`.

## #9 — Deep-pass animation issues (rec 09:23)
- **(a) Teleport:** players jump/teleport momentarily (e.g. RB and LB before the throw). Positioning glitch during the dropback phase — likely a formation/route restamp snapping a node. 
- **(b) Throw motion a bit too late:** NOTE — my `beatAt` change made the *release earlier*, not later, so "late" is likely the throw **beat** firing late in the choreography (when `throwMotion`/`runBallArc` fires relative to the dropback), OR the QB holds too long. `throwWindup=0.42` in `FootballFieldScene.swift`. Verify against the video before tuning.
- **(c) QB should hold the ball in hand:** during the dropback/pre-throw the ball isn't visibly in the QB's hand. Check `attachBall(...,chest:true)` timing for the QB before the throw.
- **(d) Tackle after catch:** after a completed catch the defenders should tackle the receiver to the ground; currently the catch plays but no tackle-down follows. Choreography: add a wrap/fall beat after the reception.

## #10 — Tackle: player sinks INTO the ground
**User:** in some tackles the player appears to go into the ground.
**Hypothesis:** the in-place fall/dive clips (`tackle_a/b`, `catch_c/catch_d` dives, `Seg_*_down/fall`) drive the root below Y=0. The `--inplace` rebase (rokoko/mixamo_retarget) zeroes the *start* offset but a fall's downward travel can still cross the turf. **Fix:** clamp the figure/root Y ≥ ground during the "fall"/held pose in `SkeletalFigure`, or add a ground clamp to the foot-lock/`didApplyAnimations` path. See rec 09:22 (run→tackle).

---

## What shipped this session (built, launches clean, UNCOMMITTED)
- Retargeted 21-clip football pack + Ochi's own actions onto the Ochi Metarig; 46-segment trimmed in-place library (`scratchpad` — regenerate via `tools/asset-pipeline/*` + `pack_segments.json` if scratchpad is gone).
- `SkeletalFigure.variantPools`: catch(×4 incl. Ochi catch-and-fall), tackle(×2), throw(×3 incl. Ochi Throw 01), celebrate(×2), juke, kick(punt+Ochi kickoff). `pickVariant` no-immediate-repeat.
- Variant-aware timing: `play(action:landAfter:beatAt:)` + `actionHitFraction`. Catch lands at ball arrival; throw release synced to ball launch via `throwWindup` (ball held in QB hand, `arriveIn`+`effectiveDuration` add the windup).
- Filled skeletal gaps: kick (PlayStep.kicker on punt/kickoff), pitch/handoff/pump-fake (throw clip), pylon-dive (dive clip).
- Clips in `Resources/PlayerClip_*.usdc`: catch_a/b/c/d, tackle_a/b, throw_a/b/c, celeb_a/b, juke_a, kick_a/b, dive (+ originals). Old Mixamo catch/throw/tackle/juke/celebrate now unused (pools point to pack/Ochi).
- Tools: `rokoko_retarget.py` (rename+strip+spine-fix+save-patch+trim+inplace+diag-render), `mixamo_retarget.py` (prefix-agnostic), `export_ochi_action.py`, `pack_segments.json`, `measure_hit.swift`, `render_strip.swift` (az/standup/window params).

---

## RESOLUTION — session 2 (2026-07-21, `BUILD SUCCEEDED`, boots clean, UNCOMMITTED)

4-bug parallel diagnose+verify+reconcile workflow (9 Opus agents, adversarial). Net: **only #10
needed new code**; the other three are false-alarms or already-fixed. All cross-checked by hand.

- **#10 — FIXED.** Confirmed root cause: in-place-rebased fall/dive/tackle clips drive a **leaf joint
  (toe/fingertip, not the pelvis)** up to ~0.30 m under the turf; nothing clamped any bone to the
  ground. Fix = per-frame ground clamp in `SkeletalFigure.updateFootLock` (4 edits): cache all bones
  (`groundBones`), add a `posing` gate (clip key `"fall"`/`"action"`) that (a) turns foot-lock OFF
  during a one-shot pose — matching the code's own "one-shot actions keep the feet free" doc — and
  (b) lifts the whole rig by the lowest bone's sub-turf deficit while posing, easing back to `yOffset`
  after. Verifier caught + fixed a CGFloat→Float compile blocker. Coordinate math hand-verified
  (container scale 1 → figure scale forced (1,1,1) → content wrapper; unit chain, so `content.position.y`
  delta == world-Y delta). **Builds + boots clean.** Confidence: medium — a per-pose high-water-mark
  clamp can trade turf-clip for slight **float** if a dive's deepest frame is a transient pointed toe
  (catch_c/dive most at risk). NEEDS on-device eyeball of a diving catch + a deep tackle.
- **#9 — implemented (session 2b, from user frame-by-frame notes).** (d) tackle-after-catch was already
  fixed in the working tree. The remaining three, now addressed:
  - **(a) teleport / "nykiminen"** — user's frame-step: *some players momentarily throw down and snap
    back to running for ~1-2 frames at step boundaries*. ROOT CAUSE = the **skeletal idle-reset race**:
    `run()` schedules `setMoving(false)` at exactly the move's `duration`, colliding with the next
    chained step's `setMoving(true)` at the same instant (`SCNAction` vs `asyncAfter` order is
    indeterminate) → ~half the time the figure flickers into the frozen idle/crouch clip for a frame.
    FIX (`FootballFieldScene.run` skeletal branch): grace the reset wait `duration → duration + 0.12`
    so the next step's existing `removeAction("skelIdleReset")` cancels it first; a genuinely finished
    mover still idles 0.12s later (invisible). (b) throw-late = left as-is (internally synced).
  - **(c) ball not in QB hand** — `attachBall` pins the ball to a fixed container offset calibrated for
    procedural-kit `arm` nodes the skinned rig lacks, so the dropback clip lifts the hands off it. FIX:
    per-frame pin the ball to the **animated hand(s)** for skeletal carriers — chest carry → midpoint of
    `hand_l`/`hand_r` (in `updateFootLocks` render hook; `SkeletalFigure.ballCarryWorldPosition`).
  - **(2) phantom fumble at the tackle** (new, from user's second note) — on a tackle the ball is left
    at the tackle spot while the carrier's body lunges forward: `fall()` plays the tackle clip whose
    root-motion lunges the body, but the **container stays put** so the container-pinned ball separates
    → reads as a fumble even though it isn't. FIX: while a fall/action pose plays (`isPosing`), pin the
    tucked ball to the **lower-torso bone** (`spine_001`) so it rides the body DOWN; a normal upright run
    keeps the stable hip offset (the one reposition at contact is masked by the tackle impact).
  `BUILD SUCCEEDED`, app runs + plays animate clean (spot-checked; poses intact). The 1-2 frame flicker
  and ball-at-tackle need on-device 120fps frame-step to confirm (sim recordings can't resolve them).
- **#8 — FALSE ALARM (no code bug).** Proven: the ONLY setter of `pendingConversion` is
  `finishOrHoldDrive`, gated on an OFFENSIVE scrimmage TD where `homeHasPossession == scorer`. There is
  **no defensive/return scrimmage-TD** in the model (PlayOutcome has no such case; INT/fumble →
  `.turnover`, 0 pts). The lone kickoff-return TD auto-resolves its PAT and never sets
  `pendingConversion`. So the "go-for-2 offered on defense" symptom cannot be produced by the engine.
  Most likely the tester saw the **defensive stop call-sheet** after the AI scored+went-for-2 (intended
  UX) and read it as a go-for-2 offer; outside chance of a save-restore Codable mismatch (unaudited).
  NEEDS a real repro (which panel appeared + preceding TD type) before any change.
- **#7 — NOT a facing bug (refuted).** Yaw is correct at every level (container yaw only ever 0 or π =
  across-LOS; only per-player ±4° jitter; stance applies pitch-only). The real, separate issue:
  `applyStance`'s limb-posing loop is a **no-op for skeletal figures** — there are no `arm`/`leg` child
  nodes under `figure`, so every player holds one frozen "Hold" idle + a rigid forward body-pitch (no
  bent knees / down hand / staggered feet). Reads as a generic, subtly-off pre-snap look, plausibly
  misperceived as "turned" from the 3/4 broadcast camera. Fix is feature-sized (role-specific frozen
  stance poses for the rig). NEEDS a screenshot from the tester's exact camera to disambiguate
  perspective vs pose-fidelity before scheduling.

## Known refinements / deferred (not bugs — polish for later)
- **Pitch & handoff** currently reuse the throw clip (overhead-ish) — user asked for dedicated clips (a true underhand toss / low handoff). No clean source in the football pack; Mixamo (interactive, user logged in) has proper Pitch/Handoff. Started exploring pack candidates (hike/holder/catch) — none ideal.
- **FG kick** has no kicker animation (PlayStep.kicker set only on punt `c.oBase` + kickoff `kBase`; FG role 0 is the holder, no clean place-kicker node).
- **Pack throw clips** are loosely trimmed (~4.9s) → compress hard to hit the 0.42s windup; may read fast. Re-trim tighter or raise throwWindup if needed. Ochi throw_c compresses least.
- **Kick foot-contact fraction** estimated at 0.5 (`measure_hit.swift` measures hands, not feet).
- **UE model** (Task: swap 3D character mesh) ON HOLD — user kept Ochi model. Separate from animations. `tools/asset-pipeline/ue_player_to_usd.py` (orientation works, texture packing WIP).
