# export_ochi_action.py — export ONE native Ochi action (already on a Metarig in the
# Ochi pack .blend) as an in-place USDC clip that transplants onto PlayerRig by bone
# name. No retarget needed (same Metarig). Mirrors rokoko_retarget's export + inplace.
#   blender -b -P export_ochi_action.py -- --blend X.blend --arm "Metarig Woman.019" \
#       --out DIR --name PlayerClip_throw_c [--inplace]
import bpy, sys, os, mathutils
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
BLEND = arg("--blend"); ARM = arg("--arm"); OUT = arg("--out", "/tmp"); NAME = arg("--name", "PlayerClip_x")
TARGET_H = 1.9
bpy.ops.wm.open_mainfile(filepath=BLEND)
scene = bpy.context.scene
keep = bpy.data.objects[ARM]
keep_meshes = [o for o in bpy.data.objects if o.type == 'MESH'
               and any(m.type == 'ARMATURE' and m.object == keep for m in o.modifiers)]
for o in list(bpy.data.objects):
    if o is not keep and o not in keep_meshes:
        bpy.data.objects.remove(o, do_unlink=True)
act = keep.animation_data.action
scene.frame_start, scene.frame_end = int(act.frame_range[0]), int(act.frame_range[1])
print("ochi: action", act.name, "frames", scene.frame_start, scene.frame_end)

# in-place: rebase root (spine + object) translation to start at origin
if "--inplace" in argv:
    n = 0
    for fc in act.fcurves:
        is_root = fc.data_path == 'location' or (fc.data_path.endswith('].location') and '"spine"' in fc.data_path)
        if not is_root or not fc.keyframe_points:
            continue
        base = fc.evaluate(scene.frame_start)
        for kp in fc.keyframe_points:
            kp.co.y -= base; kp.handle_left.y -= base; kp.handle_right.y -= base
        fc.update(); n += 1
    print("ochi: inplace rebased", n, "fcurves")

# height-normalize to game size
zs = []
for o in keep_meshes:
    for c in o.bound_box: zs.append((o.matrix_world @ mathutils.Vector(c)).z)
if zs and (max(zs) - min(zs)) > 1e-6:
    f = TARGET_H / (max(zs) - min(zs))
    keep.scale = tuple(c * f for c in keep.scale); keep.location = tuple(c * f for c in keep.location)
    bpy.context.view_layer.update()
    print("ochi: scaled x%.2f" % f)

act.name = NAME
os.makedirs(OUT, exist_ok=True)
out_path = os.path.join(OUT, f"{NAME}.usdc")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=out_path, export_animation=True, export_armatures=True,
                      export_materials=False, selected_objects_only=False, root_prim_path="/root")
print("ochi: exported ->", out_path)
