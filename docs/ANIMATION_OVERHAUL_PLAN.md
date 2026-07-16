# Animation Overhaul Plan — Madden 05-style skeletal animation

**Status:** Phase 0 (feasibility spike) DONE 2026-07-14 — the decision gate is
PASSED, the pipeline is proven end-to-end, and a compiling in-app integration
exists behind a flag. Now iterating on clip quality + wiring the gesture library
(Phase 1→2→3). Written to survive a context clear — self-sufficient for a cold
start.

## Phase 0 RESULT (2026-07-14) — decision gate PASSED, proceed with Option A
The single biggest risk (SceneKit skinned-animation export fidelity) is RETIRED
with headless evidence; no RealityKit fallback needed. What shipped this session:
- **Pipeline proven** (all headless via `swift <script>` + SceneKit on macOS):
  Blender 5.1.2 `wm.usd_export(export_armatures, export_animation)` → USD loads in
  SceneKit with a real `SCNSkinner` + a playable skeletal clip that deforms the
  mesh; clips **retarget onto any character by bone name** (load character once,
  attach clip CAAnimation to the character's `skinner.skeleton`); `clone()`
  re-skins per instance so 22 players each animate independently.
- **Assets** (`dynasty/dynasty/Resources/`): `PlayerRig.usdc` (skinned humanoid,
  19-bone standard armature, JERSEY/PANTS/SKIN/HELMET/MASK slots) +
  `PlayerClip_{run,idle,juke,tackle}.usdc`. Generator: `tools/asset-pipeline/
  player_rig.py` (`--clip <name>`; character = no --clip). The run cycle reads
  clearly as sprinting on the coach camera.
- **Integration** (compiles for iOS sim, procedural path kept as fallback):
  `UI/Match/SkeletalFigure.swift` (loader + clip library + tint + locomotion/
  action driver) wired into `FootballFieldScene` behind
  `FieldConstants.useSkeletalFigures` (auto-on when the rig asset is present):
  makePlayerNode builds the skeletal figure into the existing "figure" node;
  `run()` drives `setMoving(speed:)` instead of `swingLimbs`; idle by default.
- **Gotchas that cost time — encoded in code comments + the
  reference_scenekit_skeletal_pipeline memory:** (1) load USD Z-up (no
  `.convertToYUp`) because the option rotates the bind pose but NOT the animation
  channels → 90° pitch; stand the figure up with a wrapper. (2) standup rotation
  must nest INSIDE the facing rotation or the figure hangs below the turf. (3)
  attach clips to `skinner.skeleton`, not the armature object node (two nodes
  share the name). (4) use system time base. (5) Blender bone `Foo.L` → USD
  `Foo_L`.

## Phases 1–3 RESULT (2026-07-16) — MOCAP + hero model, live in-game
The spike graduated to a shipped-quality result. The whole path — skinned rig,
clip library, driver, integration — is validated in the running simulator.
- **Mocap, not procedural.** User feedback: hand-keyed clips read as cheap
  ([[feedback-animation-quality-bar]]). Switched to motion capture. Two sources
  were driven end-to-end (browser-automated Mixamo, then a bought pro pack):
  the procedural clips are gone.
- **Hero model = Studio Ochi "American Football" pack** (bought). Professional
  low-poly TEXTURED player (helmet+facemask, striped pads, numbered jersey,
  cleats) with its own football mocap (Run Fast, Hold, Catch&Fall, Kick, Throw)
  on a Rigify "Metarig". Converted by `tools/asset-pipeline/ochi_to_usd.py`:
  character → `PlayerRig.usdz` (texture packaged), each action → `PlayerClip_*.usdc`.
  Clips transplant onto the character by bone name (same rig). Deployed to
  `Resources/`, live in coach mode: textured players run/idle with mocab motion.
- **Pipeline is source-agnostic.** `SkeletalFigure` now finds the skinner by
  presence (not the node name "Armature"), loads `.usdz`→`.usdc`, and reparents
  all content — so Mixamo, Studio Ochi, or any rigged USD drops in. The mesh is a
  plug-in asset; swapping it reuses the driver + integration untouched.
- **Gotchas (this round):** (a) FBX imports tiny (cm) + at source scale —
  normalize to ~1.9 units in the converter. (b) FACING: the rig faces +Z (kit
  convention = downfield) after JUST the −90°X standup; a 180°Y flip pointed
  everyone the wrong way vs offense/defense — no flip. (c) Studio Ochi loco is
  already ~in-place (root drift ≈0.02u), no root-motion bake needed.

**Polish DONE (2026-07-17):** (a) TEAM COLORS — the pack's 6 uniform textures
(one UV atlas) are bundled (`uniform_0..5.png`); SkeletalFigure picks the one
nearest each team's jersey color at load, so teams read distinct + roughly match.
(b) ACTION CLIPS — throw/catch/tackle mocap wired (throwMotion→throw,
reach/overShoulder/diving→catch, wrapArms→tackle); `PlayerClip_catch` + `_kick`
exported. (c) SIZE VARIETY — scale by build (linemen bigger, skill leaner) + a
per-player jitter. Note: the pack's Man A/B/C are the SAME body (887 verts, only
different textures) — no true body-type meshes, so variety is scale-only.

**Still open:** exact per-NFL-team colors (only 6 generic uniforms exist — a real
match needs 32 team textures or a recolor), a kick/punt player beat (no kicker
gesture in the choreographer yet), and retiring the procedural kit fallback once
every beat maps.

---

**Original "immediate next" (Phase 0, now largely done):** validate in sim ✓,
tune foot-plant/skin weights (moot — pro mesh), map the gesture library
(juke→openField ✓, tackle→wrapArms ✓; catch/block/throw/stances open).

---

**Original plan (below) preserved for the full phased roadmap.**

**Goal (user's words):** "Paremmat animaatiot" — Madden 2005-style player
movement, jukes, tackles, catches: smooth, blended, momentum-based motion
with real variety, on iPad.

## Decision: Option A — skeletal rig + animation library

The current coach-mode animates **procedurally** with SCNActions on a
low-poly figure of named joint nodes (`figure`/`leg`/`legR`/`shin`/`arm`/
`armR`/`forearm`/`body`/`helmet`), no bones, no clip blending. That approach
was chosen to avoid an animation pipeline and has a **hard ceiling**: every
new move is hand-keyed joint rotations, clips can't blend, nothing compounds.

Option A (skeletal skinned mesh + a clip library + runtime blend/state
machine) is the only path where **future development compounds** — once the
substrate exists, adding a move is "author/source a clip and drop it in."
It also **subsumes** the Mixamo shortcut (Mixamo clips require a skeletal rig
anyway) and reaches Madden-level ceiling. iPad hardware (M-series) is ~100×
a 2004 console — hardware is not a constraint; the bottleneck is ART
(rigged model + clip library) and the animation-layer rewrite.

### Key architectural insight — the migration is smaller than it looks
Choreography and posing are **separable**. Everything built this session is
REUSED on top of the skeletal system:
- RouteSpec waypoint routes (who runs what), play timing / real-time pacing,
  `flightSupportMoves` (nobody freezes during ball flight), the follow/coach
  camera + framing, weather, HUD, the whole play-blocking logic.
The skeletal migration replaces only the **posing layer** — *how a limb
bends* — not the **blocking layer** — *where players go and when*. Concretely:
`PlayChoreographer` still produces per-player position/timeline data
(`PlayStep.paths`/`moves`); `FootballFieldScene` stops hand-rotating joints
and instead drives a skeletal animation state machine (locomotion blended by
speed/direction, layered action clips: juke/tackle/catch/throw/block).

## Reference target
Madden 05 hallmarks to approximate (not pixel-match — that needed mocap + a
studio art budget): motion-captured-quality locomotion, branching tackle
animations (wrap / big-hit / drag-down / gang), jukes/spins/stiff-arms that
blend out of a run cycle, catch variants with body turn, throw motion, block
engagements, momentum/weight in cuts. "Madden-05-*style*" at good quality is
achievable via Blender-authored + Mixamo-sourced skeletal clips.

## Phased plan

### Phase 0 — Feasibility spike (de-risk before committing) — SMALL
- Rig ONE player in Blender (skinned mesh + humanoid armature) sized to the
  current figure's scene units. Reuse/adapt `tools/asset-pipeline/player_kit.py`
  geometry as the skin.
- Author/source 3 clips: run cycle, one juke, one tackle. (Mixamo for run is
  fine for the spike; football-specific from Blender.)
- Export as a format SceneKit loads with a skinner + `SCNAnimationPlayer`
  (USD/`.scn`/DAE — verify skinning survives export; the kit pipeline already
  documents USD quirks).
- Load in `FootballFieldScene`, drive it from ONE play's existing
  `PlayStep.paths` (speed → locomotion blend; trigger the tackle clip at the
  contact step). Record video, run `tools/motion_profile.py`, compare
  side-by-side to the current procedural figure.
- **Decision gate:** does skeletal read clearly better on our field/camera,
  and does existing choreography drive it cleanly? If yes → proceed. If the
  export/skinning path is too painful in SceneKit, evaluate RealityKit /
  Reality Composer Pro before committing (bigger rewrite, more modern tooling).

### Phase 1 — Skeletal substrate (the reusable engine) — LARGE
- Standard humanoid skeleton (bone naming convention) + skinned player mesh
  with team-color material slots (JERSEY/PANTS/HELMET/SKIN...) preserved so
  re-tinting still works (`applyUniform`/`setUniforms`).
- `SCNSkinner` load path + cached clip library loader (like the current kit
  loader but for `SCNAnimationPlayer` clips).
- Runtime blend/state machine: base locomotion (idle ↔ walk ↔ jog ↔ sprint
  blended by speed, plus turn lean/bank), layered one-shot action clips
  (juke/spin/stiff-arm/catch/tackle/block/throw) that blend in over
  locomotion and out again. Momentum/weight on cuts.
- Adapter: `PlayChoreographer` timeline → skeletal driver. Keep the procedural
  path behind a flag as a fallback during migration (don't delete until
  parity is proven).

### Phase 2 — Starter clip library — LARGE (art-heavy)
Minimum viable set, per the animation vocabulary already designed in code
(so we know exactly what's needed): idle/breathing, run cycle, cut/plant,
juke (jab-step), spin, stiff-arm, hurdle; catch (reach / over-shoulder /
diving / toe-tap) with body turn; tackle (wrap / big-hit / ankle-dive /
drag-down / gang); block engage (drive / anchor / pancake / whiff); throw
(overhand / sidearm / off-foot / lob / bullet) + pump; snap exchange; QB
dropback; huddle; referee signals. Source: Blender-authored + Mixamo for
generic locomotion. Deterministic per-player signature selection (reuse the
existing `hash01(playerId+...)` variant-selection so a player keeps a style).

### Phase 3 — Integration + parity — MEDIUM
Wire every existing choreography beat to skeletal clips: RouteSpec routes,
flightSupportMoves (everyone moving during ball flight), tackle contact,
catch turn, block engagement, pre-snap stances (3-point/2-point/split),
weather, camera. Prove no regression: ball leaves QB's hand, camera follows,
no flight freezes — via the video motion-profile method (`analyze-app` skill
+ `tools/motion_profile.py`). Then retire the procedural fallback.

### Phase 4 — Expansion (compounding, ongoing) — INCREMENTAL
Each future round adds CLIPS, not engine code: more tackle/juke variants,
position-specific signatures, situational animations (celebrations,
injuries, sideline). This is the payoff of A — cheap per addition.

## Asset pipeline
- Blender 5.1.2 + blender-mcp + uv already installed; `tools/asset-pipeline/`
  holds `player_kit.py` (procedural geometry) — extend with an armature +
  animation-export script (`player_rig.py` / `animations.py`).
- Verify skinned-mesh + skeletal-animation export into SceneKit early
  (Phase 0) — this is the single biggest technical risk.
- Mixamo (free Adobe mocap) for generic humanoid locomotion, retargeted to
  the standard skeleton; football-specific actions authored in Blender.

## Risks
1. **SceneKit skinned-animation export fidelity** — verify in Phase 0; RealityKit
   is the fallback engine if SceneKit's skinner path is too limited.
2. **Art volume** — the clip library is the real cost; Phase 2 is weeks of
   art work. Mitigate with Mixamo for locomotion, incremental delivery.
3. **Performance** — 22 skinned meshes + blending; budget on device early
   (current procedural figures are ~2k tris each; skinned meshes + skeleton
   are heavier). Test FPS on a real iPad, not just simulator.
4. **Parity regression** — keep procedural fallback behind a flag until the
   skeletal path passes the same video/motion gates.

## Verification (every phase)
Video, not stills: record from simulator, extract frames, run
`tools/motion_profile.py`, judge motion the way the `analyze-app` skill v2
prescribes. Side-by-side procedural-vs-skeletal for the migration.

## Prerequisites (start after these are committed)
- #41 attribute↔mechanics wiring (in flight, `wf_c9ca35a4-b56`) + its balance calcs.
- #40 draft-class analysis.
(Once those land, clear context and begin at Phase 0.)
