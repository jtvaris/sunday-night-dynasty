# Blender Game Asset Pipeline — Reference

Concrete `bpy`/`bmesh` recipes and checklists for Dynasty asset work. All code
runs headless: `blender -b -P script.py -- <args>`. Parse args after `--`:

```python
import sys
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
```

`bpy.data` = direct data (fast, reliable). `bpy.ops` = operators (need correct
active/selected context). `bpy.context` = current state. Use `mathutils` for
vector/quat/matrix math (bundled).

---

## 1. Procedural modeling

### Raw mesh + bmesh

```python
import bpy, bmesh
# from_pydata for static meshes
mesh = bpy.data.meshes.new("Part"); mesh.from_pydata(verts, [], faces); mesh.update()
obj = bpy.data.objects.new("Part", mesh); bpy.context.collection.objects.link(obj)

# bmesh for anything built with ops (extrude/subdivide/per-face)
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r0, radius2=r1,
                      depth=length, matrix=mat)          # tapered capsule/limb
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=r)  # joint/head
bm.to_mesh(obj.data); bm.free(); obj.data.update()       # ALWAYS free()
```

For **10k+ faces prefer bmesh over repeated `bpy.ops`** (operators have per-call
overhead). This is exactly how `player_rig.py` / `player_mesh_v2.py` build limbs
(tapered cones) and joints (spheres).

### Watertight, auto-riggable body

Auto-riggers (Mixamo) reject fragmented/blobby meshes. Overlap solid primitives,
then unify into ONE connected surface:

```python
rem = obj.modifiers.new("Remesh", 'REMESH'); rem.mode = 'VOXEL'; rem.voxel_size = 0.03
bpy.context.view_layer.objects.active = obj
bpy.ops.object.modifier_apply(modifier="Remesh")
bpy.ops.object.shade_smooth()
```

### Modifiers (subsurf / mirror / array / boolean / solidify / bevel)

```python
m = obj.modifiers.new("Sub", 'SUBSURF'); m.levels = 2
m = obj.modifiers.new("Mir", 'MIRROR'); m.use_axis = (True, False, False); m.use_clip = True
m = obj.modifiers.new("Sol", 'SOLIDIFY'); m.thickness = 0.1
bpy.ops.object.modifier_apply(modifier="Sub")   # object must be active+selected
```

### Named material slots (SceneKit re-tints by name)

```python
for name in ("JERSEY","PANTS","SKIN","HELMET","MASK"):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    obj.data.materials.append(mat)
for poly in obj.data.polygons:        # assign faces to a slot by index
    poly.material_index = slot_for(poly)
```

---

## 2. Armature, skinning, weights

### Build bones (edit mode) then constraints/poses (pose mode)

```python
import bpy
arm_data = bpy.data.armatures.new("Rig"); arm = bpy.data.objects.new("Rig", arm_data)
bpy.context.collection.objects.link(arm); bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for name, head, tail, parent, connect in bone_defs:     # names must match the clips!
    b = arm_data.edit_bones.new(name); b.head, b.tail = head, tail
    if parent: b.parent = arm_data.edit_bones[parent]; b.use_connect = connect
bpy.ops.object.mode_set(mode='OBJECT')
```

### Skinning + weight rules

- Parent mesh to armature with automatic weights, then clean up:
  `bpy.ops.object.parent_set(type='ARMATURE_AUTO')`.
- **Concentrate edge loops + weight around joints**; follow the deformation path.
- **Normalize** weights (each vertex sums to 1) and **mirror** L↔R for symmetry.
- Fewer bones = cheaper at runtime; don't add bones the animation never drives.
- After any mesh mirror/duplication, **recalculate normals** (see gotchas).

### IK/FK for authoring (bake before export)

```python
bpy.ops.object.mode_set(mode='POSE')
ik = arm.pose.bones["Forearm.L"].constraints.new('IK')
ik.target = bpy.data.objects["IK_Target"]; ik.pole_target = bpy.data.objects["IK_Pole"]
ik.chain_count = 2          # 0 = solve whole chain to root
```

IK/FK, drivers, and constraints are **authoring conveniences** — bake them to raw
keyframes before export (`bpy.ops.nla.bake(...)`), because USD/SceneKit read only
baked bone transforms, not constraints.

---

## 3. Clip authoring

### Keyframes + F-curve interpolation

```python
import bpy, math
arm.animation_data_create(); act = bpy.data.actions.new("run"); arm.animation_data.action = act
bpy.ops.object.mode_set(mode='POSE')
thigh = arm.pose.bones["thigh.L"]
for angle, frame in [(-30,1),(0,13),(30,25)]:
    thigh.rotation_euler = (math.radians(angle),0,0)
    thigh.keyframe_insert(data_path="rotation_euler", frame=frame)
for fc in act.fcurves:
    for kp in fc.keyframe_points:
        kp.interpolation = 'BEZIER'   # CONSTANT hold / LINEAR mechanical / BEZIER organic
        kp.easing = 'EASE_IN_OUT'
```

### F-curve modifiers — loop + jitter

```python
z = act.fcurves.find("location", index=2)
cyc = z.modifiers.new(type='CYCLES'); cyc.mode_before = cyc.mode_after = 'REPEAT'   # loop a stride
noise = z.modifiers.new(type='NOISE'); noise.strength, noise.scale = 0.3, 5.0        # organic jitter
```

`data_path` must match RNA exactly: `"location"`, `"rotation_euler"`, `"scale"`,
`'["custom_prop"]'`. Bone channels live under `pose.bones["name"]`.

### In-place rebase (kill root drift the game container supplies itself)

The container node supplies world movement, so clips play in place. Rebase the
root (spine + object) translation to start at the origin — this is what
`export_ochi_action.py --inplace` does:

```python
for fc in act.fcurves:
    is_root = fc.data_path == 'location' or ('"spine"' in fc.data_path and fc.data_path.endswith('.location'))
    if not is_root or not fc.keyframe_points: continue
    base = fc.evaluate(scene.frame_start)
    for kp in fc.keyframe_points:
        kp.co.y -= base; kp.handle_left.y -= base; kp.handle_right.y -= base
    fc.update()
```

For sliced tackle/fall segments that still drift or float, run `strip_root.py`
(horizontal always; `--seat` for grounded falls). Its header explains why the
runtime ground clamp only ever *lifts*, so a fall clip must drive the body DOWN.

### The 12 animation principles (the quality lens)

Squash/stretch, anticipation, staging, straight-ahead vs pose-to-pose,
follow-through & overlap, slow-in/slow-out, arcs, secondary action, timing,
exaggeration, solid drawing, appeal. For this project the ones that most often
separate "Madden-2005" from "stiff": **weight** (grounded contacts, no float),
**follow-through/overlap** (pads, arms lag the torso), **arcs** (limbs swing on
curves, not lines), **timing** (live-speed cadence, not metronomic).

---

## 4. Topology / UV / retopo checklist

**Topology**
- **Quads for anything that deforms** (limbs, torso). Triangles are fine for
  static hard-surface if intentional. **N-gons are never acceptable** in final
  deforming geometry.
- Even edge density; concentrate loops at bend/joint areas, sparse where nothing
  deforms.
- No non-manifold edges (an edge shared by >2 faces) — invisible in viewport,
  catastrophic for physics/skinning. Check with `Select > All by Trait >
  Non-Manifold` or bmesh `is_manifold`.
- A clean 5k-tri mesh beats a messy 3k-tri mesh.

**UV**
- UV islands should follow the **silhouette**, not arbitrary cuts.
- Keep **consistent texel density** across islands (inconsistency is the tell of
  amateur work).
- Place seams where they're least visible.

**Retopo / LOD** (only if perf demands it — one hero rig is cheap)
- Retopo from a sculpt to clean quads before rigging; decimation preserves the
  silhouette but wrecks edge flow — retopo when the mesh must deform.
- LOD0 close / LOD1 mid / LOD2 far; reduce material + texture res per level.

---

## 5. Headless render (verification)

Render key frames or a turntable to eyeball a mesh/clip before an on-device run.

```python
import bpy, math
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'          # fast preview; CYCLES for final
scene.render.resolution_x = scene.render.resolution_y = 1080
scene.render.film_transparent = True                 # RGBA cutout
# three-point-ish: key + fill + rim
for loc, energy, size in [((4,-3,5),800,3),((-3,-2,3),300,4),((0,4,4),500,2)]:
    bpy.ops.object.light_add(type='AREA', location=loc)
    L = bpy.context.active_object.data; L.energy, L.size = energy, size
bpy.ops.object.camera_add(location=(5,-5,3)); cam = bpy.context.active_object
cam.constraints.new(type='TRACK_TO').target = subject
scene.camera = cam
# single frame
scene.render.filepath = "/tmp/preview.png"; bpy.ops.render.render(write_still=True)
# turntable: orbit the camera, one PNG per angle, then ffmpeg to mp4
```

CLI shortcut: `blender scene.blend -b --render-output /tmp/f_ --render-frame 1`.
Render **image sequences, not direct-to-video** (a mid-render crash keeps the
frames). Combine with `ffmpeg -framerate 24 -i /tmp/f_%03d.png out.mp4`.

### Verification harness — `render_verify.py` (the committed one-command tool)

Don't re-derive a per-session renderer. `tools/asset-pipeline/render_verify.py`
is the standing harness: clip(s) in → a labeled **contact sheet** (side profile +
3/4 game-like view at start/25/50/75/end) **and** machine-readable numeric checks,
non-zero exit on failure. Use it before copying any clip into `Resources/`.

```bash
# one or more PlayerClip_*.usdc → sheets + checks in --out
blender -b -P tools/asset-pipeline/render_verify.py -- \
    dynasty/dynasty/Resources/PlayerClip_run.usdc \
    dynasty/dynasty/Resources/PlayerClip_stance3.usdc --out /tmp/verify

# a fall/tackle: add --fall to run the monotonic root-descent check
blender -b -P tools/asset-pipeline/render_verify.py -- \
    dynasty/dynasty/Resources/PlayerClip_tackle_a.usdc --fall --out /tmp/verify

# a .blend + action instead of a USDC clip
blender -b -P tools/asset-pipeline/render_verify.py -- \
    --blend pack.blend --arm "Metarig Woman.019" --action MyClip --out /tmp/verify
```

What it prints per clip (and emits as JSON between `###RENDER_VERIFY_BEGIN###` /
`###RENDER_VERIFY_END###`):
- **`lowest_head_z` min/max/final** — the lowest bone HEAD's world Z per frame
  (bone heads = SceneKit joint nodes = what the runtime ground clamp minimises).
- **`ground_contact`** — the deepest approach to turf (z=0). FAIL if the clip
  **floats** (never within `--float-tol`, default 0.10, of the turf) or is
  **buried** (sinks past `--sink-tol`, default 0.50). Locomotion feet plant near 0;
  a seated fall dips a hair below (the lift-only clamp seats it flush).
- **`fall_descent`** (only with `--fall`) — the `--root-bone` (default `spine`) must
  drop `>= --min-descent` (0.20) start→end **and** never rise more than `--max-rise`
  (0.15) above its start. This is the **"flies into the sky" detector** that cost a
  whole July session: a mis-seated fall whose root travels UP fails here.

Exit code is non-zero if ANY check on ANY clip fails → wire it into a gate/CI.

Calibration proven on the shipped clips (2026-07-23):
`run` grounded PASS; `stance3` grounded PASS; `tackle_a --fall` descent PASS
(spine 0.83→0.21, no rise) now that it is `strip_root.py --seat` seated;
`fall_back --fall` PASS. The check FIRES correctly on: a **run mis-flagged `--fall`**
(net descent ≈0 → FAIL) and the **pylon `dive` flagged `--fall`** (rises 0.84 → FAIL) —
confirming `--fall` must NOT be used on a genuine airborne leap.

Implementation notes (match these if you extend it): render engine is
`BLENDER_WORKBENCH` (fast, no texture deps — the clips' `./textures/` warnings are
benign and materials are overridden); the camera is **grounded on the measured foot
plane** and aimed with `to_track_quat('-Z','Y')` because `TRACK_TO` constraints don't
evaluate headless; framing **tracks the figure per frame** at a fixed zoom (clips may
carry forward drift the game plays in-place, so a union-fit would shrink the figure to
a dot); the figure meshes are captured **before** the turf plane is added so the plane
never pollutes the framing bbox; frame labels are burned in via the render **note
stamp** (all other stamp fields disabled); the contact sheet is montaged with numpy
(bundled) and saved through a Blender image (no PIL).

---

## 6. FBX / USD export gotchas (the silent killers)

- **Apply scale AND rotation before export. No exceptions.** A rig imported at
  scale 0.01 bakes wrong and you won't notice until after skinning:
  `bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)`.
- **Recalculate normals after any mirror/duplicate** — flipped normals render as
  black/inside-out (teeth, inner limbs are classic):
  `bpy.ops.mesh.normals_make_consistent(inside=False)` in edit mode.
- **Bone names must match across character + every clip** (transplant is by name).
  Mixamo ships `mixamorig:Hips`; strip the prefix (see `mixamo_to_usd.py`). Some
  packs ship `mixamorig_` (underscore) + Reallusion `RL_*` helper bones —
  normalize to canonical names (see `rokoko_retarget.py`).
- **Y-up vs Z-up.** Blender is Z-up; USD/most engines Y-up. Build to the project
  convention (§conventions in SKILL.md) so the loader's standup lands the figure
  facing downfield with feet on the turf.
- **Drop empty meshes** some FBX packs ship (e.g. an empty Woman mesh in the Ochi
  Man file): `[o for o in bpy.data.objects if o.type=='MESH' and not o.data.vertices]`.
- **Character → `.usdz`** (textures packaged), **clips → `.usdc`** (animation only).
- Retarget rest-pose mismatch: Mixamo is a **T-pose**, the Ochi Metarig an
  **A-pose**. A naive copy twists the arms. Use Rokoko (rest-pose alignment) or the
  world-delta method (roll-agnostic) — never a raw local-rotation copy.

---

## 7. Batch / scene hygiene

```python
def clear_scene():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    for coll in (bpy.data.meshes, bpy.data.materials):
        for b in coll:
            if b.users == 0: coll.remove(b)
# start from empty for deterministic headless runs:
bpy.ops.wm.read_factory_settings(use_empty=True)
```

Batch across `.blend`/FBX with `bpy.ops.wm.open_mainfile()` /
`bpy.ops.import_scene.fbx()` in a loop; write outputs to NEW paths, never
overwrite source assets.
