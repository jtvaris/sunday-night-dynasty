---
name: blender-game-asset-pipeline
description: >-
  Author, retarget, and export 3D player assets for the Dynasty SceneKit
  football game with headless Blender 4.x (bpy/bmesh). Use when generating or
  editing meshes procedurally, building or fixing armatures/skinning, authoring
  or retargeting mocap clips onto the Ochi Metarig, stripping/seating root
  motion, exporting USD/USDC/USDZ for SCNSkinner, running headless verification
  renders, or debugging topology / UV / FBX-scale / bone-name / orientation
  problems in the tools/asset-pipeline/ scripts. Triggers: "bpy", "bmesh",
  "Blender script", "retarget", "Mixamo", "Rokoko", "Ochi Metarig", "USDC clip",
  "strip root", "in place", "player mesh", "rig", "skinning", "weight paint",
  "topology", "retopo", "UV unwrap", "headless render", "export FBX/USD".
  NOT for Swift/SceneKit runtime playback code (that lives in SkeletalFigure.swift)
  and NOT for GPU shader/material effects (use scenekit-shader-vfx).
---

# Blender Game Asset Pipeline (Dynasty)

Headless Blender is how this project makes every 3D player asset: procedural
meshes, skinned rigs, and mocap clips that transplant onto `PlayerRig` **by bone
name** and load into SceneKit as an `SCNSkinner`. This skill is the map + the
recipes. **Read the real scripts before editing them** — they already encode the
hard-won conventions below.

## The project pipeline (read these first)

All scripts run headless: `blender -b -P tools/asset-pipeline/<script>.py -- <args>`.

| Script | Purpose |
|--------|---------|
| `tools/asset-pipeline/player_rig.py` | Build the skinned humanoid mesh + armature (bmesh) → `PlayerRig.usdc`; also bakes `run/idle/juke/tackle` clips. `--mesh` emits an OBJ for Mixamo auto-rig upload. |
| `tools/asset-pipeline/player_mesh_v2.py` | Watertight, connected, riggable body from solid primitives + **voxel remesh** (Mixamo auto-rig accepts it; metaballs did not). |
| `tools/asset-pipeline/player_kit.py` | Low-poly **named part kit** (HELMET_SHELL, TORSO, THIGH…) sized to swap under existing joint nodes. |
| `tools/asset-pipeline/rokoko_retarget.py` | **Preferred** retarget: Mixamo clip → Ochi Metarig via the Rokoko addon (aligns T-pose vs A-pose rest poses, so arm-driven motion transfers). Exports in-place USDC. |
| `tools/asset-pipeline/mixamo_retarget.py` | Hand-rolled world-delta retarget (roll-agnostic). In-place by default; `--root` keeps hip translation. Fallback when Rokoko is unavailable. |
| `tools/asset-pipeline/mixamo_to_usd.py` | Mixamo FBX (character or clip) → USD; strips the `mixamorig:` prefix so keyPaths match. |
| `tools/asset-pipeline/ochi_to_usd.py` | Studio Ochi football FBX → textured USDZ character + one USDC clip per named action (same Metarig, no retarget). |
| `tools/asset-pipeline/export_ochi_action.py` | Export ONE native Ochi action from a `.blend` as an in-place USDC clip. |
| `tools/asset-pipeline/ue_player_to_usd.py` | UE-style football-player FBX → oriented/scaled character USDZ with PBR textures. |
| `tools/asset-pipeline/strip_root.py` | Strip horizontal root travel (in-place); `--seat` also drives the vertical so a fall/tackle lays flat on the turf. |
| `tools/asset-pipeline/pack_segments.json` | Frame ranges that slice the football-mocap packs into named clips. |

Context docs: `docs/ANIMATION_OVERHAUL_PLAN.md`, and the memory notes
`reference_scenekit_skeletal_pipeline`, `reference_pack_retarget_pipeline`.
Runtime playback + foot-lock/ground-clamp is Swift:
`dynasty/dynasty/UI/Match/SkeletalFigure.swift`.

## Non-negotiable conventions (get these wrong and it breaks silently)

- **Bone-name transplant.** A clip drives the character by identical bone names.
  Every clip AND the character must share the SAME skeleton (names + hierarchy).
  Blender **`Foo.L` exports to USD/SceneKit as `Foo_L`** (dot → underscore) —
  animation keyPaths use the underscore form.
- **Orientation.** Build Blender **Z-up**, character stands along **+Z**, **faces +Y**,
  **feet at z=0**. USD export is Y-up: Blender +Z(up)→scene +Y, Blender
  +Y(front)→scene +Z (downfield). The Swift loader applies a −90° X standup.
- **Scale.** 1 Blender metre = 1 scene unit = 1 yard. Height-normalize characters
  to `TARGET_H = 1.9`. **Apply scale/rotation before export** (see gotchas).
- **Material slots by name** — SceneKit re-tints by these exact names:
  `JERSEY, PANTS, SKIN, HELMET, MASK, BALL, LACES, SHOE`.
- **Character → `.usdz`** (packages textures). **Clips → `.usdc`** (animation only).
- **Ochi Metarig bones** (Rigify): `spine`, `spine.001..006`, `shoulder.L/R`,
  `upper_arm.L/R`, `forearm.L/R`, `hand.L/R`, `thigh.L/R`, `shin.L/R`, `foot.L/R`,
  `toe.L/R`. See `mixamo_retarget.py` `MAP` for the mixamorig→Metarig mapping.

## Fastest path per task

- **New/edited body mesh** → bmesh in `player_rig.py`/`player_mesh_v2.py`; keep it a
  single watertight component (voxel remesh) if it must be auto-rigged. Recipes:
  `reference.md` §Procedural Modeling.
- **New locomotion/action clip** → prefer a native Ochi action (`export_ochi_action.py`)
  or Mixamo via **`rokoko_retarget.py`**; fall back to `mixamo_retarget.py`. Always
  in-place unless the container needs root travel. Then `strip_root.py` if it drifts.
- **Fall/tackle floats or slides** → `strip_root.py --seat` (per-frame ground seat);
  do NOT seat genuinely airborne clips (pylon dive) — it kills the leap. Full
  rationale is in the `strip_root.py` header.
- **Verify before committing** → headless render turntable / key frames (recipe in
  `reference.md` §Headless Render) and, for motion, an on-device look. Quality bar
  is **Madden-2005 mocap**; procedural jog-in-place does not clear it.

## Deep reference

`reference.md` in this folder holds the recipe library and checklists:
procedural modeling (from_pydata/bmesh/modifiers/remesh), armature + IK/FK +
weight/skinning, clip authoring (keyframes, F-curve interp/Cycles/Noise, NLA,
bake), topology/UV/retopo rules, headless render/lighting/camera, and the
FBX/USD export gotcha list (scale-not-applied, flipped normals, mismatched bone
names, Y-up/Z-up). Consult it for concrete `bpy` code.

---

### Attribution & licenses

Synthesized and re-framed for this project from:
- **majiayu000/claude-skill-registry** (MIT) — `metal-shader-expert` sibling aside,
  the `3d-modeling` skill (upstream **omer-metin/skills-for-antigravity**, Apache-2.0):
  production topology/UV/export "battle scars" adapted into the gotcha + rules lists.
- **Andrew1326/dominations** `.claude/skills/blender-*` (Apache-2.0, author
  "terminal-skills") — bpy/bmesh modeling, animation, and render-automation recipes
  in `reference.md`.
- **DavinciDreams/Agent-Team-Plugins** `teams/3d-design` (no LICENSE file present in
  repo) — topology / rigging / animation / optimization checklists were **paraphrased
  and re-derived** (generic industry knowledge), not copied, and reframed for iOS/USD.
- **phuetz/code-buddy** — the "Blender Automation" skill was **not found**: the repo's
  default branch has no committed working tree (only `cb2/*` feature branches, none
  containing a Blender skill). Nothing taken.

Project conventions above are original to Dynasty (`tools/asset-pipeline/`).
