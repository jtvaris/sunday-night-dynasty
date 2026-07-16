# ochi_to_usd.py — convert the Studio Ochi American Football pack (textured,
# rigged, animated FBX) into game assets: a textured character (USDZ, so the
# texture is packaged) + one USDC clip per named action. The character and every
# clip share the same Rigify "Metarig" skeleton, so clips transplant onto the
# character by bone name (same mechanism as the Mixamo path,
# reference_scenekit_skeletal_pipeline). No Mixamo / retargeting needed.
#
#   blender -b -P ochi_to_usd.py -- --in ANIM.fbx --out DIR --name PlayerRig --character
#   blender -b -P ochi_to_usd.py -- --in ANIM.fbx --out DIR --name PlayerClip_run --action "Run Fast"
#
# Character -> .usdz (texture packaged). Clips -> .usdc (animation only).

import bpy, sys, os, mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
IN = arg("--in")
OUT = arg("--out", "/tmp/ochi_usd")
NAME = arg("--name", "PlayerClip")
ACTION = arg("--action")           # substring match against action names
IS_CHARACTER = "--character" in argv
TARGET_H = 1.9

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.fbx(filepath=IN)

# drop empty meshes (the Man file ships an empty Woman mesh)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) == 0]:
    bpy.data.objects.remove(o, do_unlink=True)

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# pick the action for a clip (else bind pose for the character)
has_anim = False
if not IS_CHARACTER and ACTION:
    match = [a for a in bpy.data.actions if ACTION.lower() in a.name.lower()]
    if match:
        if arm.animation_data is None: arm.animation_data_create()
        arm.animation_data.action = match[0]
        fr = match[0].frame_range
        scene.frame_start = int(fr[0]); scene.frame_end = int(fr[1])
        match[0].name = NAME
        has_anim = True
        # Note: the Studio Ochi locomotion clips are authored essentially
        # in-place (verified: root horizontal drift ≈0.02 units), so no root-
        # motion baking is needed — the container supplies downfield movement.
        print("ochi: action", match[0].name, "frames", int(fr[0]), int(fr[1]))
else:
    # character: strip animation so it exports at the bind/rest pose
    if arm.animation_data: arm.animation_data.action = None
    scene.frame_set(0)

# normalize height so the character is game-sized (feet ~y0, ~1.9 units tall)
zs = []
for o in [x for x in bpy.data.objects if x.type == 'MESH']:
    for c in o.bound_box:
        zs.append((o.matrix_world @ mathutils.Vector(c)).z)
height = (max(zs) - min(zs)) if zs else 0.0
if height > 1e-6:
    f = TARGET_H / height
    arm.scale = tuple(c * f for c in arm.scale)
    arm.location = tuple(c * f for c in arm.location)
    bpy.context.view_layer.update()
    print(f"ochi: scaled x{f:.2f} ({height:.3f} -> {TARGET_H})")

os.makedirs(OUT, exist_ok=True)
ext = "usdz" if IS_CHARACTER else "usdc"
out_path = os.path.join(OUT, f"{NAME}.{ext}")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=out_path, export_animation=(has_anim),
                      export_armatures=True, export_materials=True,
                      selected_objects_only=False, root_prim_path="/root")
print("ochi: exported", ("character" if IS_CHARACTER else "clip"), "->", out_path)
