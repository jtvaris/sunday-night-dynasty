# 3D / Animation Pipeline — Current-State Baseline & Skills-First Reframe

**Author:** analysis agent · **Date:** 2026-07-23 · **Branch:** `feat/skeletal-mocap-players`
**Scope:** everything 3D/animation in the coach-mode football renderer — runtime scene,
skinned-rig playback, the mocap→USD asset pipeline, and the visual-quality bar. Read-only
audit; no code touched.

> Companion history: `docs/ANIMATION_OVERHAUL_PLAN.md` (Phase 0–3 result),
> `docs/PLAN_play_direction_and_reverse.md` (Plan A/B mirror + REVERSE), `TODO.md` top sections.

---

## TL;DR

- **What exists is real and shipped.** The Animation Overhaul reached its own goal: 22
  independently-animated **skinned mocap players** (Studio Ochi hero mesh) run/juke/catch/
  throw/tackle/kick/celebrate + hold per-position pre-snap stances, driven by a clip-transplant
  system that retargets arbitrary football mocap onto one shared rig by bone name. It reads as a
  competent **PS2 / Madden-2000-era** football game (see `/tmp/plan_b_verify_2026-07-23/04_field.png`).
- **The pipeline is the crown jewel and the bespoke part.** `tools/asset-pipeline/` (10 scripts +
  `pack_segments.json`) does something no off-the-shelf tool does: retarget → trim → per-frame
  ground-seat falls → USDC export that transplants into SceneKit by bone name, around SceneKit's
  Z-up / animation-channel gotchas. Meshy/Tripo/Blender-MCP do **not** replace this — they feed it.
- **The 3 biggest quality gaps vs the "Madden 2005 mocap" bar:**
  1. **Locomotion is one run clip stride-scaled** — no walk/jog/sprint blend, no cut/plant/turn
     footwork. Direction change is container-yaw + body-lean, not steps. This is the foundational gap.
  2. **Player identity/materials are generic** — 6 pack uniform atlases picked by nearest-color,
     with a **baked duplicate number** on every jersey (all OL read "10" in
     `07_play_b_action.png`); the real per-player number only shows on a dim floating billboard.
     No 32-team colors, no per-player mesh number.
  3. **Contact variety + world life are thin** — 5 choreographed tackle branches but only
     `tackle_a`/`tackle_b`/`fall_back` clips (visual repetition, frozen held end-poses); empty
     sidelines, flat speckled-texture crowd, a crude procedural referee.
- **Skills-first reframe, in one line:** the **verification loop** moves to XcodeBuildMCP
  (retire idb ×0.688 pixel math) + a standardized Blender render harness; **asset generation**
  (uniforms, body-type variants, props, crowd) moves to Meshy / Tripo / Blender-MCP; the
  **retarget+transplant core stays bespoke** — and, as of this session, **has already been packaged
  as the `blender-game-asset-pipeline` project skill** (a companion `scenekit-shader-vfx` skill for
  GPU/material work is being populated alongside it). Recommendation #2 below is therefore "adopt +
  extend" rather than "create".
- **Top-5 plan items:** (1) migrate sim QA to XcodeBuildMCP `snapshot_ui` [S]; (2) package
  `tools/asset-pipeline` as a `dynasty-mocap-pipeline` skill [S]; (3) standardize the headless
  clip-render harness [S]; (4) real per-team uniforms + per-player numbers via Meshy Retexture [M];
  (5) locomotion blend set (walk/jog/sprint/cut) — the run at the quality bar [L].

---

# PART 1 — INVENTORY (what exists, how it's implemented)

## 1.1 Runtime 3D architecture — who calls whom

The renderer is a SceneKit (`SCNScene`) subsystem living under `dynasty/dynasty/UI/Match/`. The
**logical→scene boundary** is crisp: `PlayChoreographer` + `RouteSpec` are pure geometry/timeline
functions that never touch SceneKit; `FootballFieldScene` consumes their `PlayStep` output and is the
only thing that moves nodes and plays clips.

| File | Size | Role |
|---|---|---|
| `FootballFieldScene.swift` | 280 KB, ~5 400 ln | The `SCNScene`. Owns **field** (surface, mow stripes, yard lines/numbers, hashes, sidelines, goalposts, `buildStadium`, pylons, markers, referee, ball), **cameras** (`buildCamera`, `focusCamera`, `CameraStyle`, `viewFacing`/`lateralSign` mirroring, replay cams), **lighting/weather**, and **play execution** (`runPlay`→`execute(step:)`→`run(node:to:)`, throw/catch/tackle/fall gestures). |
| `SkeletalFigure.swift` | 37 KB | Skinned-rig playback driver (one per player). Clip transplant by bone name, locomotion state machine, foot-lock IK, ground clamp, action/stance clips, ball-carry pinning, team-uniform texturing. |
| `PlayChoreographer.swift` | 137 KB | Pure play geometry/timeline: formations, RouteSpec routes, tackle/gang steps, snap/handoff/throw beats → `PlayStep` list. |
| `RouteSpec.swift` | 19 KB | Single source of truth for play shapes; `resolve()` LOS-relative→world; `diagram()` projects the SAME data to the 2D card. |
| `PlayDiagramView.swift` | 11 KB | 2D X&O playbook card (draws from `RouteSpec.diagram`). |
| `SceneKitFieldView.swift` | 4 KB | `UIViewRepresentable` wrapper. Its `Coordinator` is the `SCNSceneRendererDelegate` that drives `updateFootLocks` every frame + DEBUG FPS. |
| `PlayReplay.swift` | 2 KB | `RecordedPlay` value struct — restage a play under a replay camera. |

**Three coexisting player-rendering paths, one active.** `makePlayerNode`
(`FootballFieldScene.swift:4966`) builds a `container → figure` node then branches on
`FieldConstants.useSkeletalFigures` (`:35`, = `SkeletalFigure.isAvailable`, auto-on when
`PlayerRig.usdz` is in the bundle):

1. **Skeletal (live):** `SkeletalFigure(...)` added under `figure`, registered in
   `skeletalFigures[ObjectIdentifier(figure)]` (`:5001-5010`).
2. **Kit (fallback):** `buildKitFigure` from `PlayerKit.usdc` (`:5011`).
3. **Procedural (fallback):** `buildProceduralFigure` — hand-built capsule joints
   `leg/legR/shin/arm/armR/forearm` (`:5070`).

Every downstream gesture checks `skeletalDriver(for: figure)` (`:4928`) and forks: `run()`
locomotion (`:1948`), `applyStance` (`:985`), `fall`/`wrapArms` (`:2662`/`:2785`),
`reach`/`divingCatch`/`toeTapReach` (`:2200`/`:2277`/`:2313`), `throwMotion`/`pitchMotion`
(`:3502`/`:3590`), `pumpFake`, `performOpenFieldMove`, `celebrationJump`, `pylonDive`,
`resetGait` (`:2997`). The **procedural kit path is dead weight in practice** — it only runs if the
rig asset is missing — but every gesture still carries its two-branch code.

**The skinned-figure driver (`SkeletalFigure.swift`) — the interesting engineering:**

- **Clip transplant by bone name** (`clip()` `:107-120`): load each `PlayerClip_*.usdc` **Z-up**
  (`.convertToYUp: false`), pull the first animated node's `CAAnimation`, cache it, and attach it to
  the character's `skinner.skeleton` — retargets onto any same-rig character.
- **Locomotion state machine** (`setMoving` `:309-350`, `locoClipSpeed` `:363-370`): idle / run /
  backpedal all from **one** run clip. Playback rate = `groundSpeed ÷ (runV0·figureScale)` so the
  planted foot tracks the turf; backpedal reverse-plays it; idle freezes on a per-player frame.
  Cadence is driven from the container's **actual per-frame ground speed** (`updateFootLock`
  `:417-424`) so a stopped body's legs settle instead of churning.
- **Foot-lock IK** (`:376-475`): 2-bone `SCNIKConstraint` per ankle, proximity-damped so it can only
  ever *reduce* slide, never pop. Runs from `didApplyAnimationsAtTime` (`SceneKitFieldView.swift:65`).
- **Ground clamp** (`:487-496`): lift-only — while a held ground pose plays (`isGrounded`, `:502`),
  raise the whole rig so the lowest bone never sinks under turf. This is why falls must be
  **seated downward at author time** (see `strip_root.py --seat`) — the runtime cannot lower a
  floating body.
- **One-shot actions + variety** (`play(action:)` `:581-606`, `variantPools` `:64-72`,
  `actionHitFraction` `:83-89`, `actionTargetDuration` `:50-55`): an action resolves to a random
  non-repeating pool variant, compressed to a football-appropriate duration, and time-shifted so its
  **beat** (catch grab / throw release / tackle contact) lands at a game event (`landAfter`/`beatAt`).
- **Stances** (`playStance` `:614-623`): held final-frame clip per position, mapped in
  `applyStance` (`FootballFieldScene.swift:987-994`): threePoint→`stance3`, twoPoint→`stance2`,
  split→`stanceSplit`, underCenter→`stanceUC`, upright→`stanceUpright`.
- **Ball-carry pinning** (`ballCarryWorldPosition` `:559`, `pinCarriedBallToBody`
  `FootballFieldScene.swift:4956`): a carried ball rides the animated hands (QB dropback) or lower
  torso (tuck through a tackle) instead of a fixed belt offset the skinned rig lacks.

**Camera mirroring** (`viewFacing` `:1083`, `lateralSign` `:1092`): the world is mirrored in X by
`lateralSign = -viewFacing` at the scene data-in boundary so the 3D field's left/right matches the
2D playbook card for both home and away framings (Plan A, shipped uncommitted). `RouteSpec.resolve`
(`:65-77`) additionally carries a `mirror` factor for the REVERSE button (Plan B) — three separate
multiplicative lateral factors (`mirror` · `sideSign` · `screenSign`) that must not double-negate.

## 1.2 Assets — the clip library

Bundled in `dynasty/dynasty/Resources/`: **30** `PlayerClip_*.usdc` + `PlayerRig.usdz` (255 KB, the
textured Ochi hero mesh) + `PlayerKit.usdc` (67 KB, procedural fallback parts) + `uniform_0..5.png`
(6 team atlases).

| Category | Clips (size KB) | Source |
|---|---|---|
| **Locomotion** | `run` 347, `sprint` 347, `idle` 347 | Studio Ochi native (in-place, root drift ≈0.02u) |
| **Stance** (held) | `stance3` 181, `stance2` 181, `stanceSplit` 181, `stanceUC` 181, `stanceUpright` 181 | Hand-authored in Blender (IK-posed, baked). **⚠ Being re-authored by another agent right now** — `/tmp/stance_fix_2026-07-23/` (`mk3.py`, `sw_*.usdc` CROUCH/BENDS sweep). |
| **Tackle / fall** | `tackle_a` 203 (diving tackler), `tackle_b` 203 (getting hit), `fall_back` 199 (big-hit backward), `dive` 276 (pylon dive), `tackle` 347 (legacy) | 21-clip pack, retargeted; `tackle_a/b` re-stripped via `strip_root.py --seat` |
| **Catch** | `catch_a` 289, `catch_b` 223, `catch_c` 274, `catch_d` 347, `catch` 393 (legacy) | pack ×3 + Ochi Catch-and-Fall (`catch_d`) |
| **Throw** | `throw_a` 423, `throw_b` 477, `throw_c` 277, `throw` 569 (legacy) | pack ×2 + Ochi Throw 01 (`throw_c`) |
| **Kick** | `kick_a` 353, `kick_b` 268, `kick` 347 (legacy) | pack punt + Ochi kickoff |
| **Juke** | `juke_a` 366, `juke` 233 (legacy) | Mixamo dodge, retargeted (`mixamo_retarget.py`) |
| **Celebrate** | `celeb_a` 313, `celeb_b` 296, `celebrate` 410 (legacy) | pack spike / arms-up |

**Provenance summary:** hero mesh + its native mocap (`run/idle/sprint/kick/catch_d/throw_c`) from
the **bought Studio Ochi "American Football" pack**; the `_a/_b/_c` variants from a **21-clip bought
football-mocap pack** retargeted via **Rokoko** (catalog in `pack_segments.json`); `juke` from
**Mixamo**; stances + `fall_back` **hand-authored in Blender**. The single-name legacy clips
(`catch`/`throw`/`tackle`/`kick`/`celebrate`/`juke`/`idle`) are superseded by the `_a/_b` variants
and appear to be **unreferenced dead weight** (not in `SkeletalFigure.variantPools`) — a bundle-size
cleanup candidate (~2 MB).

## 1.3 Pipeline — `tools/asset-pipeline/`

Flow: **source FBX/mocap → retarget (or native export) → trim + strip/seat root → height-normalize
1.9u → USDC/USDZ export (`root_prim /root`) → copy to `Resources/` (synced, auto-bundles) →
runtime transplant by bone name**.

| Script | What it does |
|---|---|
| `rokoko_retarget.py` | Mixamo/pack clip → Ochi Rigify Metarig via the **Rokoko** addon (proper T-pose↔A-pose rest alignment, so **arm-driven** motion — throw/catch/celebrate — transfers). Renames `mixamorig_`→`mixamorig:`, strips Reallusion helper bones, overrides the spine chain, patches a Rokoko crash. Trim window + `--inplace` root rebase. |
| `mixamo_retarget.py` | Lightweight **world-delta** retarget Mixamo→Metarig (roll-agnostic). Correct for legs/spine/hips; **DAMPS arm motion** (T-pose vs A-pose rest mismatch) — so it's used for locomotion/juke; arm clips come from Ochi/pack instead. |
| `strip_root.py` | Flatten horizontal spine-root translation (fall plays in place). `--seat` mode: per-frame ground-seat so the lowest bone sits a hair under turf (the lift-only runtime clamp then seats it flush). Gain-measured exact linear correction. **NOT** for genuine airborne clips (pylon dive). |
| `ochi_to_usd.py` | Ochi pack FBX → textured character USDZ (`--character`) or one in-place USDC clip per named action (`--action "Run Fast"`). |
| `export_ochi_action.py` | Export one native Ochi action straight from a `.blend` (same Metarig, no retarget) with `--inplace` root rebase. |
| `mixamo_to_usd.py` | Mixamo character/clip FBX → USD with `SCNSkinner` (strip `mixamorig:` prefix, height-normalize, region materials by height). The Phase-0 path before the Ochi hero. |
| `ue_player_to_usd.py` | Unreal-style "American Football Player" FBX → character USDZ with PBR textures — an **alternative hero-model** path (unused in the shipped bundle). |
| `player_rig.py` | Procedural skinned humanoid + clip authoring (Phase-0 substrate; 19-bone standard armature, JERSEY/PANTS/SKIN/HELMET/MASK slots). Superseded by the Ochi hero. |
| `player_kit.py` / `player_mesh_v2.py` | Procedural part-kit geometry / a watertight remeshed body for Mixamo auto-rig upload — the early art path. |
| `pack_segments.json` | Segment catalog for the 21-clip pack: each 19 s take sliced into reusable segments (`lo/hi` fraction + game-situation `cat`: stance/hike/throw/catch/tackle_make/tackle_hit/fall/getup/kick/…). **This is a map of clip content that isn't fully mined yet** (getup, spike, holder, react segments exist but aren't wired). |

**SceneKit gotchas encoded in the pipeline + `SkeletalFigure` (the tribal knowledge):** load Z-up
(the `.convertToYUp` option rotates the bind pose but not the animation channels → 90° pitch);
attach clips to `skinner.skeleton` not the armature object node; Blender bone `Foo.L` → USD `Foo_L`;
export only the target armature (a stray Mixamo source armature hijacks the loader's "first animated
node"); falls must be seated downward because the runtime clamp is lift-only.

## 1.4 Visual-quality evidence & honest read vs the "Madden 2005 mocap" bar

**Evidence:** `/tmp/plan_a_verify_2026-07-23/` (20 shots, Plan A field↔card mirror),
`/tmp/plan_b_verify_2026-07-23/` (REVERSE button + play actions),
`/tmp/stance_fix_2026-07-23/` (the **other agent's live** stance-authoring workspace —
`before_stance*` renders, `sw_*.usdc` preset sweep, `mk3.py`/`render_clip.py`/`camtest.py`).
Inspected directly: `04_field.png` (pre-snap) and `07_play_b_action.png` (dropback in motion).

**Reads well:**
- Clean, legible **field**: green grass with mow stripes, yard numbers, hash marks, white sidelines,
  yellow LOS + blue first-down lines, goalposts, a dark stadium bowl, night floodlights.
- **Textured players** with helmets/facemasks, shoulder pads, numbered jerseys, cleats — a clear step
  above stick figures. Pre-snap **stances read** (linemen have a hand near the turf).
- Locomotion **foot-plant** is solid (the stride-sync + foot-lock work) — no obvious skating.

**Still stiff / short of the bar:**
1. **Generic uniform identity** — the 6-atlas nearest-color scheme bakes the SAME number into every
   jersey (all interior OL show **"10"** in `07_play_b_action.png`); the real per-player number is
   only the dim floating billboard. No true team colors.
2. **Ball detaches** — in `07_play_b_action.png` the ball floats slightly ahead of the QB's hands
   despite the per-frame pin; reads a touch off.
3. **Awkward mid-play blends** — a blocking lineman caught down on one knee reads as a collapse.
   SceneKit has no blend tree; crossfades hide state changes but action→loco transitions can pop.
4. **Locomotion is one clip** — stride-scaled run only; no walk/jog/sprint set, no cut/plant/turn
   footwork. Direction change = container yaw + `run()` body-lean/bank (`:1985-1990`), not steps.
5. **Contact repetition** — 5 choreographed tackle branches (`tackleSteps`
   `PlayChoreographer.swift:1584`, gang via `gangTacklers`/`pileOnMoves` `:798`/`:814`) but only
   `tackle_a`/`tackle_b`/`fall_back` clips; held end-poses can freeze (the `tackle_a` "leg-up" sprawl,
   flagged in TODO). No **getup** — downed men don't rise.
6. **Dead sideline / crowd** — `buildStadium` (`:4245`) is a lofted rounded-rect bowl with a
   procedural **speckle crowd texture** (`crowdTexture` `:4352`); the referee (`buildReferee`
   `:4417`) is a crude procedural blob; benches/chain-crew/props are absent.

---

# PART 2 — "AS IF BUILT WITH THE NEW SKILLS" MAPPING

For each area: which skill/tool **would own it** in a skills-first workflow, what that workflow looks
like, and what stays genuinely bespoke.

### A. Sim verification / on-device visual QA → **XcodeBuildMCP + ios-simulator (skill: `xcodebuildmcp-cli`)**
- **Today:** `idb` coordinate math scaled by **×0.688** for the iPad Pro, hand-computed tap points,
  `simctl` launch + manual screenshot dirs (`project_sim_automation` memory; the `/tmp/plan_*_verify`
  loops). Fragile and re-derived per session; a play-clock had to be toggled **OFF** to beat tap
  latency (`TODO.md:14` — must be restored to `-string 10`).
- **Skills-first:** `xcodebuildmcp build-and-run` → `snapshot_ui` returns the **semantic
  accessibility hierarchy**, so taps target elements by id (AUDIBLE, REVERSE, a play card) instead of
  pixel math; `screenshot` + log capture standardize the evidence. The whole verify loop becomes one
  reproducible script. `visual-design-loop` / `analyze-app` provide the judge step.
- **Bespoke remaining:** the *choice* of what to verify (mirror correctness, fall-monotonicity,
  ball-in-hand) — but the mechanics stop being hand-rolled.

### B. Player hero model & body-type variants → **Meshy (skill) / Tripo (MCP) / Blender-MCP**
- **Today:** ONE bought Ochi mesh (887 verts); body-type variety is **scale-only** (Man A/B/C are the
  same body — `ANIMATION_OVERHAUL_PLAN.md:67-69`).
- **Skills-first:** Meshy `text-to-image (a-pose/t-pose, multi-view) → image-to-3d → auto-rig` (rig
  includes free walk/run) or Tripo `generate+rig+animate→glb` to produce **lineman / skill / QB
  builds**. Blender-MCP Sketchfab/Hyper3D as alternates.
- **Bespoke remaining:** Meshy/Tripo emit **their own** skeleton — retargeting their mesh onto our
  fixed Ochi Metarig so existing clips still transplant is our glue (see D).

### C. Uniforms / team colors / numbers → **Meshy Retexture (skill) / a texture-gen skill**
- **Today:** 6 generic atlases, nearest-color pick, duplicate baked number (`SkeletalFigure.swift:
  257-294`).
- **Skills-first:** Meshy **Retexture** (10 credits/pass) → 32 team atlases from a prompt/reference;
  OR keep one clean UV and render per-player numbers as decals (the procedural path already has
  `addNumberDecals` `FootballFieldScene.swift:3756`).
- **Bespoke remaining:** the load-time material swap (`applyUniform`) — trivial to extend to 32.

### D. The mocap retarget + USD transplant core → **STAYS BESPOKE → now the `blender-game-asset-pipeline` skill**
- No market tool does "retarget arbitrary football mocap onto our exact shared Metarig, seat falls
  per-frame for a lift-only runtime clamp, export USDC that transplants into SceneKit by bone name,
  around the Z-up/animation-channel gotchas." Meshy/Tripo auto-rig **create** a skeleton; they do not
  solve **name-matched transplant onto a fixed rig**, nor the SceneKit quirks, nor the ground-seat
  math. **This is already realized:** `.claude/skills/blender-game-asset-pipeline/SKILL.md` now maps
  all 10 scripts + `pack_segments.json`, the non-negotiable conventions (bone-name transplant,
  Z-up/+Y-face/feet-at-0, `TARGET_H=1.9`, material slot names, the `Foo.L`→`Foo_L` rule, the
  Metarig bone list), and a `reference.md` recipe library. Part 3 #2 is now "adopt + extend it".

### E. Clip verification / render harness → **`blender-game-asset-pipeline` skill + Blender-MCP viewport**
- **Today:** ad-hoc per-clip renders re-invented each session (`rokoko_retarget --diag`; the other
  agent's `render_clip.py`/`camtest.py`/`mk3.py` in `/tmp/stance_fix_2026-07-23/`; the tackle
  session's lowest-bone-Z-monotonicity proof). The pattern is stable but the *concrete script* is
  still re-derived — the new skill's `reference.md` has a "Headless Render" recipe section but no
  committed one-command harness yet.
- **Skills-first:** commit one harness script (clip in → side + 3/4 render + per-frame lowest-bone-Z
  report) into `tools/asset-pipeline/` and point the skill's recipe at it; Blender-MCP
  `get_viewport_screenshot` for interactive spot-checks.

### G. GPU materials / VFX / atmosphere → **`scenekit-shader-vfx` skill (being populated)**
- **Today:** materials are plain PBR/`.constant` with emissive tricks (floodlights `:4335`, crowd
  emissive `:4300`); weather is `SCNParticleSystem`. No custom shaders.
- **Skills-first:** the companion `scenekit-shader-vfx` skill (dir present, content landing) is the
  owner for `SCNShadable`/`SCNProgram`/Metal material work — turf wetness, jersey sheen, stadium-light
  bloom tuning, particle upgrades. Pairs with F (crowd/atmosphere) for the "living stadium" push.

### F. Stadium / crowd / sideline / props → **Blender-MCP (PolyHaven, Sketchfab, Hyper3D) + Meshy/Tripo**
- **Today:** procedural lofted bowl + speckle-texture crowd + crude ref; no benches/chains/towers.
- **Skills-first:** Blender-MCP PolyHaven HDRIs/textures + Sketchfab stadium/crowd/bench models;
  Meshy/Tripo for hero props (chain crew, Gatorade, camera towers, goalpost pads). Crowd → a low-poly
  Sketchfab crowd or animated billboard sprites.

**One-line ownership map:**

| Area | Owner in a skills-first world |
|---|---|
| Build / run / log / UI taps / screenshots | XcodeBuildMCP (`xcodebuildmcp-cli`), ios-simulator MCP |
| Hero mesh + body variants | Meshy / Tripo / Blender-MCP |
| Uniforms / textures / numbers | Meshy Retexture |
| Stadium / crowd / props / HDRI | Blender-MCP (PolyHaven/Sketchfab/Hyper3D), Meshy |
| GPU materials / shaders / VFX | `scenekit-shader-vfx` skill (being populated) |
| Clip QA render harness | `blender-game-asset-pipeline` skill (add committed harness script) |
| **Retarget → seat → USD transplant** | **BESPOKE — already the `blender-game-asset-pipeline` skill** |

---

# PART 3 — IMPROVEMENT PLAN (prioritized, concrete)

Effort key: **S** = hours, **M** = a few days, **L** = a week+. Each item names the skill/tool and
how success is verified.

## Quick wins (this week)

1. **[S] Migrate sim QA to XcodeBuildMCP.** Replace idb ×0.688 pixel math with `build-and-run` +
   `snapshot_ui` semantic taps + `screenshot`. Codify the `plan_*_verify` coached-game loop as a
   reusable script. *Also restore the play-clock* (`playClockSetting -string 10`, toggled off in the
   test sim per `TODO.md:14`). **Skill:** `xcodebuildmcp-cli` / ios-simulator. **Verify:** a scripted
   run reproduces the mirror + REVERSE screenshots with zero coordinate math.
2. **[S — mostly DONE] Adopt + extend the `blender-game-asset-pipeline` skill.** This session already
   packaged `tools/asset-pipeline` + `pack_segments.json` + the SceneKit conventions into
   `.claude/skills/blender-game-asset-pipeline/SKILL.md` (with a `reference.md` recipe library).
   Remaining: cross-link it from the memory files so agents load the skill instead of re-deriving the
   flow, and add the render harness (#3) as a committed recipe. **Verify:** a fresh agent adds a new
   clip using only the skill doc.
3. **[S] Standardize the headless clip-render harness.** Commit one script into `tools/asset-pipeline/`:
   USDC in → side + 3/4 render + per-frame lowest-bone-Z report (for fall monotonicity). Generalizes
   `render_clip.py` / the tackle proof; wire it into the skill's "Headless Render" recipe. **Verify:**
   reproduces the fall-seat monotonicity check from the 2e tackle session.
4. **[S] Retire legacy dead clips.** `catch`/`throw`/`tackle`/`kick`/`celebrate`/`juke`/`idle`
   single-name USDCs appear unreferenced (not in `variantPools`); confirm and drop to reclaim ~2 MB.
   **Verify:** `grep` the codebase for each name; build; bundle shrinks, nothing breaks.

## Medium (asset quality)

5. **[M] Real per-team uniforms + per-player numbers.** Meshy **Retexture** → 32 team atlases, OR
   render per-player number decals on one clean UV. **Skill:** `meshy-3d-generation`. **Verify:**
   formation-camera screenshot (XcodeBuildMCP) shows correct team colors + distinct numbers.
6. **[M] Body-type variant meshes.** Meshy/Tripo auto-rig → lineman / skill / QB builds, retargeted
   onto the Metarig via the pipeline skill. **Verify:** side-by-side silhouette render + on-device
   formation shot.
7. **[M] Close the flagged animation gaps (TODO polish).** (a) pylon-dive **tail-seat** float
   (`strip_root` variant that seats only the final held pose, keeps the leap); (b) trim the
   `tackle_a` held "leg-up" sprawl tail; (c) author an **own dive-clip** for the diving tackler
   (today it reuses the faller's clip); (d) wire **getup** so downed men rise (segments already
   cataloged in `pack_segments.json`). **Skill:** `dynasty-mocap-pipeline` + render harness.
   **Verify:** render monotonicity + on-device.
8. **[M] Sideline & prop life.** Blender-MCP PolyHaven/Sketchfab benches, chain crew, camera towers,
   goalpost pads; Meshy for hero props. **Verify:** broadcast-camera screenshot shows a populated
   sideline.

## Larger (closing to the Madden-2005 bar)

9. **[L] Locomotion blend set — the single biggest lift.** Author/source **walk + jog + sprint +
   backpedal + cut/plant + turn** clips and a real speed/direction blend. SceneKit has no blend tree,
   so either layer crossfading weights (extend `setMoving`) or migrate only the **posing layer** to
   RealityKit / Reality Composer Pro, which *has* blend trees — `ANIMATION_OVERHAUL_PLAN.md` already
   names RealityKit as the sanctioned fallback engine, and the choreographer/camera/blocking layers
   are untouched by such a swap. **Skill:** `dynasty-mocap-pipeline` + Meshy/Tripo animate for source.
   **Verify:** motion-profile video + `analyze-app` judge; foot-plant holds through cuts.
10. **[L] Contact variety.** Expand the fall/tackle library into real distinct clips
    (wrap / big-hit / drag-down / ankle / gang), mined from the `pack_segments.json`
    `tackle_make`/`tackle_hit`/`fall`/`getup` segments the choreographer already asks for. **Verify:**
    run 20 plays; no two identical hits; every downed man gets up.
11. **[L] Crowd + atmosphere.** Real crowd (low-poly Sketchfab crowd or animated billboard sprites),
    PolyHaven HDRI sky, upgraded stadium shell, plus a materials pass (turf wetness, jersey sheen,
    light bloom). **Skills:** Blender-MCP for assets, `scenekit-shader-vfx` for the GPU/material work.
    **Verify:** broadcast + replay camera reads as a living stadium, holds FPS on a real iPad (not just
    sim — per the overhaul plan's perf risk).

---

## Appendix — key file:line references

- Player build branch: `FootballFieldScene.swift:4966` (`makePlayerNode`), `:5001-5017` (3-path fork),
  `:35` (`useSkeletalFigures`).
- Skeletal driver: `SkeletalFigure.swift` — clip loader `:107`, `setMoving` `:309`, `locoClipSpeed`
  `:363`, `updateFootLock`/ground-clamp `:406-497`, `play(action:)` `:581`, `playStance` `:614`,
  `variantPools` `:64`, `actionHitFraction` `:83`.
- Frame hook: `SceneKitFieldView.swift:65` (`didApplyAnimationsAtTime` → `updateFootLocks`);
  `FootballFieldScene.swift:4937` / `:4956` (`updateFootLocks` / `pinCarriedBallToBody`).
- Stance map: `FootballFieldScene.swift:985-996`.
- Camera/mirror: `viewFacing` `:1083`, `lateralSign` `:1092`; `RouteSpec.resolve` `:65-77`,
  `diagram` `:361`.
- Tackle geometry: `PlayChoreographer.swift:1584` (`tackleSteps`), `:798`/`:814`
  (`gangTacklers`/`pileOnMoves`).
- Stadium/crowd/ref: `FootballFieldScene.swift:4245` (`buildStadium`), `:4352` (`crowdTexture`),
  `:4417` (`buildReferee`).
- Screenshots: `/tmp/plan_b_verify_2026-07-23/04_field.png`, `.../07_play_b_action.png`;
  live stance-authoring `/tmp/stance_fix_2026-07-23/`.
</content>
</invoke>
