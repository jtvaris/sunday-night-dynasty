# Animation Overhaul Plan — Madden 05-style skeletal animation

**Status:** Planned. Start after the in-flight sim/feature work is committed
(see "Prerequisites"). Written to survive a context clear — this doc is
self-sufficient for a cold start.

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
