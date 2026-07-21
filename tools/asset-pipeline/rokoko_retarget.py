# rokoko_retarget.py — retarget a Mixamo clip onto the Ochi Rigify Metarig using
# the free Rokoko Studio Live addon's retargeter, which aligns the two rigs' rest
# poses (Mixamo T-pose vs Ochi A-pose) properly — so ARM-driven motion (throw,
# catch, celebrate) transfers, which the hand-rolled world-delta retarget damped.
# Exports a USDC clip that transplants onto PlayerRig.usdz by bone name.
#
#   blender -b -P rokoko_retarget.py -- --in CLIP.fbx --rig OCHI_ANIM.fbx \
#           --out DIR --name PlayerClip_throw
import bpy, sys, os, mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
MIXAMO = arg("--in"); RIG = arg("--rig"); OUT = arg("--out", "/tmp/rk"); NAME = arg("--name", "PlayerClip")
TARGET_H = 1.9

bpy.ops.wm.read_factory_settings(use_empty=True)
try: bpy.ops.preferences.addon_enable(module="rokoko")
except Exception as e: print("rokoko enable:", e)
scene = bpy.context.scene

# --- import target (Ochi Metarig) ---
bpy.ops.import_scene.fbx(filepath=RIG)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) == 0]:
    bpy.data.objects.remove(o, do_unlink=True)
ochi = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
ochi.animation_data_clear()

# --- import source (Mixamo); drop its mesh so height-normalize + export stay clean ---
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=MIXAMO)
new = set(bpy.data.objects) - before
mix = next(o for o in new if o.type == 'ARMATURE')
for o in [o for o in new if o.type == 'MESH']:
    bpy.data.objects.remove(o, do_unlink=True)
mix_frames = mix.animation_data.action.frame_range if mix.animation_data and mix.animation_data.action else (1, 30)
scene.frame_start, scene.frame_end = int(mix_frames[0]), int(mix_frames[1])
print("rokoko: source frames", int(mix_frames[0]), int(mix_frames[1]))

# --- normalise the source skeleton to canonical Mixamo names ---
# This pack ships `mixamorig_` (underscore) + Reallusion (RL_*) helper bones, which
# Rokoko's auto-detect does NOT recognise (0 hits). A hand-built bone list retargets
# without Rokoko's rest/roll bookkeeping and curls the spine. So instead we RENAME the
# core bones back to `mixamorig:` (colon) — making the source identical to a plain
# Mixamo rig — and let auto-detect + its full rest handling do the retarget.
ren = {}
for b in mix.data.bones:
    if b.name.startswith("mixamorig_"):
        ren[b.name] = "mixamorig:" + b.name[len("mixamorig_"):]
for old, new in ren.items():
    mix.data.bones[old].name = new
# make sure the action fcurves point at the renamed bones (fix any Blender left behind)
if mix.animation_data and mix.animation_data.action:
    for fc in mix.animation_data.action.fcurves:
        for old, new in ren.items():
            tok = '"%s"' % old
            if tok in fc.data_path:
                fc.data_path = fc.data_path.replace(tok, '"%s"' % new)
print("rokoko: renamed", len(ren), "source bones mixamorig_ -> mixamorig:")

# strip the Reallusion helper bones (RL_*, RootNode_*, floor bones) so what's left is
# a plain 65-bone Mixamo skeleton — identical to the clips whose auto-detect mapped
# cleanly. With the extras present, auto-detect collapses the spine chain and leaves a
# rigid forward-pitched torso.
bpy.context.view_layer.objects.active = mix
bpy.ops.object.mode_set(mode='EDIT')
removed = 0
for b in list(mix.data.edit_bones):
    if not b.name.startswith("mixamorig:"):
        mix.data.edit_bones.remove(b); removed += 1
bpy.ops.object.mode_set(mode='OBJECT')
print("rokoko: stripped", removed, "non-mixamorig bones,", len(mix.data.bones), "remain")

# --- Rokoko retarget (auto-detect) ---
scene.rsl_retargeting_armature_source = mix
scene.rsl_retargeting_armature_target = ochi
bpy.ops.rsl.build_bone_list()
# fix the spine chain: auto-detect scrambles it because the Metarig has BOTH `pelvis.L`
# and `spine`, so it maps Hips->pelvis.L and slides Spine2->spine etc. Override the
# whole spine chain in-place with the known-correct Mixamo->Rigify mapping (arms/legs
# auto-map correctly and keep their rest handling).
SPINE_FIX = {
    "mixamorig:Hips": "spine", "mixamorig:Spine": "spine.001", "mixamorig:Spine1": "spine.002",
    "mixamorig:Spine2": "spine.003", "mixamorig:Neck": "spine.005", "mixamorig:Head": "spine.006",
}
tgt_names = {b.name for b in ochi.data.bones}
by_src = {i.bone_name_source: i for i in scene.rsl_retargeting_bone_list if i.bone_name_source}
for src, tgt in SPINE_FIX.items():
    if src not in {b.name for b in mix.data.bones} or tgt not in tgt_names:
        continue
    it = by_src.get(src) or scene.rsl_retargeting_bone_list.add()
    it.bone_name_source = src; it.bone_name_target = tgt
# de-dup: keep the first source per target, clear the rest (retarget aborts on dups).
seen = set()
for it in scene.rsl_retargeting_bone_list:
    t, s = it.bone_name_target, it.bone_name_source
    if not (t and s):
        continue
    if t in seen:
        it.bone_name_source = ""
    else:
        seen.add(t)
auto = len([i for i in scene.rsl_retargeting_bone_list if i.bone_name_source and i.bone_name_target])
print("rokoko: auto-mapped", auto, "of", len(scene.rsl_retargeting_bone_list), "bones (deduped)")
# Rokoko persists edited mappings to a "custom scheme" after retargeting and crashes on
# our in-place spine overrides (KeyError on unregistered detection keys). We don't need
# that persistence — no-op it so only the retarget math runs.
try:
    import importlib
    _csm = importlib.import_module("rokoko.core.custom_schemes_manager")
    _csm.save_retargeting_to_list = lambda *a, **k: None
    print("rokoko: patched save_retargeting_to_list -> no-op")
except Exception as e:
    print("rokoko: could not patch save_retargeting_to_list:", e)
try:
    bpy.ops.rsl.retarget_animation()
    print("rokoko: retarget_animation OK")
except Exception as e:
    print("rokoko: retarget FAILED:", repr(e))

if arg("--diag"):
    import mathutils as _mu
    fs, fe = scene.frame_start, scene.frame_end
    for i in range(11):
        f = int(fs + (fe - fs) * i / 10)
        scene.frame_set(f); bpy.context.view_layer.update()
        sp = ochi.pose.bones.get("spine.003")
        m = ochi.matrix_world @ sp.matrix
        sdir = ((m @ _mu.Vector((0, sp.length, 0))) - m.to_translation()).normalized()
        hr = (ochi.matrix_world @ ochi.pose.bones["hand.R"].matrix).to_translation()
        print("rokoko: f%d spineZdir=%.2f handR_Z=%.2f" % (f, sdir.z, hr.z))
    # Blender-native render of a window (ground truth, no SceneKit/root-motion ambiguity)
    outd = arg("--diagout", "/tmp")
    lo, hi = float(arg("--diaglo", "0.80")), float(arg("--diaghi", "1.0"))
    sc = scene
    engs = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engs else 'BLENDER_EEVEE'
    sc.render.resolution_x = 300; sc.render.resolution_y = 460
    wd = bpy.data.worlds.new("w"); sc.world = wd; wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs[1].default_value = 2.6
    # key + fill sun so poses read clearly (world-only was too dark)
    for ang, en in (((-0.6, 0.2, 0.5), 4.0), ((0.5, 0.3, -0.4), 1.5)):
        L = bpy.data.objects.new("L", bpy.data.lights.new("L", 'SUN')); L.data.energy = en
        L.rotation_euler = ang; sc.collection.objects.link(L)
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
    N = int(arg("--diagn", "6"))
    for i in range(N):
        f = int(fs + (fe - fs) * (lo + (hi - lo) * i / max(1, N - 1))); sc.frame_set(f); bpy.context.view_layer.update()
        xs = []; ys = []; zs = []
        for o in [o for o in bpy.data.objects if o.type == 'MESH']:
            for c in o.bound_box:
                wv = o.matrix_world @ _mu.Vector(c); xs.append(wv.x); ys.append(wv.y); zs.append(wv.z)
        cx = (min(xs) + max(xs)) / 2; cy = (min(ys) + max(ys)) / 2; cz = (min(zs) + max(zs)) / 2
        span = max(max(xs) - min(xs), max(zs) - min(zs), 1.2)
        cam.location = (cx + span * 1.5, cy - span * 2.4, cz + span * 0.15)
        cam.rotation_euler = (_mu.Vector((cx, cy, cz)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = "%s/tgt_%02d.png" % (outd, i); bpy.ops.render.render(write_still=True)
    print("rokoko: rendered target window", lo, hi, "->", outd)

# --- the target now carries the retargeted action; drop source, name, export ---
bpy.data.objects.remove(mix, do_unlink=True)
if ochi.animation_data and ochi.animation_data.action:
    ochi.animation_data.action.name = NAME

_act = ochi.animation_data.action if ochi.animation_data else None

# --- trim to an action window (fractions of the take) and rebase to frame 0 ---
TRIMLO = float(arg("--trimstart", "0")); TRIMHI = float(arg("--trimend", "1"))
if _act and (TRIMLO > 0 or TRIMHI < 1):
    span = scene.frame_end - scene.frame_start
    lo_f = scene.frame_start + int(round(span * TRIMLO))
    hi_f = scene.frame_start + int(round(span * TRIMHI))
    for fc in _act.fcurves:
        for kp in fc.keyframe_points:
            kp.co.x -= lo_f; kp.handle_left.x -= lo_f; kp.handle_right.x -= lo_f
        fc.update()
    scene.frame_start, scene.frame_end = 0, hi_f - lo_f
    print("rokoko: trimmed window %.2f-%.2f -> frames 0..%d" % (TRIMLO, TRIMHI, hi_f - lo_f))

# --- in-place: REBASE root translation so the clip starts at origin. Unlike stripping
# it, this keeps the in-window dynamism (throw step, dive lunge, fall) but removes the
# take's net walk so the figure plays where the game anchors it. Run AFTER trim so the
# first keyframe is the window start. ---
if "--inplace" in argv and _act:
    n = 0
    for fc in _act.fcurves:
        is_root = fc.data_path == 'location' or (fc.data_path.endswith('].location') and '"spine"' in fc.data_path)
        if not is_root or not fc.keyframe_points:
            continue
        base = fc.evaluate(scene.frame_start)
        for kp in fc.keyframe_points:
            kp.co.y -= base; kp.handle_left.y -= base; kp.handle_right.y -= base
        fc.update(); n += 1
    print("rokoko: inplace — rebased", n, "root-location fcurves to origin")

zs = []
for o in [x for x in bpy.data.objects if x.type == 'MESH']:
    for c in o.bound_box: zs.append((o.matrix_world @ mathutils.Vector(c)).z)
if zs and (max(zs) - min(zs)) > 1e-6:
    f = TARGET_H / (max(zs) - min(zs))
    ochi.scale = tuple(c * f for c in ochi.scale); ochi.location = tuple(c * f for c in ochi.location)
    bpy.context.view_layer.update()
    print(f"rokoko: scaled x{f:.2f}")

os.makedirs(OUT, exist_ok=True)
out_path = os.path.join(OUT, f"{NAME}.usdc")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=out_path, export_animation=True, export_armatures=True,
                      export_materials=False, selected_objects_only=False, root_prim_path="/root")
print("rokoko: exported ->", out_path)
