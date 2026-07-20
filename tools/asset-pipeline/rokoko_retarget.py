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

# --- Rokoko retarget ---
scene.rsl_retargeting_armature_source = mix
scene.rsl_retargeting_armature_target = ochi
bpy.ops.rsl.build_bone_list()
mapped = [(i.bone_name_source, i.bone_name_target) for i in scene.rsl_retargeting_bone_list]
print("rokoko: auto-mapped", len([m for m in mapped if m[1]]), "of", len(mapped), "bones")
for s, t in mapped:
    if not t: print("   UNMAPPED source:", s)
try:
    bpy.ops.rsl.retarget_animation()
    print("rokoko: retarget_animation OK")
except Exception as e:
    print("rokoko: retarget FAILED:", repr(e))

# --- the target now carries the retargeted action; drop source, name, export ---
bpy.data.objects.remove(mix, do_unlink=True)
if ochi.animation_data and ochi.animation_data.action:
    ochi.animation_data.action.name = NAME

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
