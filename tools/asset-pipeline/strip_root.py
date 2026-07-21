# Strip the HORIZONTAL root (spine) translation from a clip so it plays IN PLACE.
#
# The tackle/fall/dive segments (pack_segments.json) are sliced from run-into-tackle
# mocap, so the dive/hit carries the actor's forward run momentum — the "spine" root
# fcurve walks ~5.5 units (≈ several yards in-game) which drags the whole mesh off the
# tackle spot: the RB "runs on" past the whistle and tacklers scatter. `--inplace` only
# rebased the START to origin (kept the in-window walk on purpose). For a fall we want
# NO horizontal travel: zero the X/Z root fcurves to their start value. The vertical (Y,
# along the up-pointing spine bone) is KEPT so the pelvis still drops to the ground — the
# body lays out flat where he was tackled instead of moonwalking downfield.
#
# Usage: blender --background --python strip_root.py -- <in.usdc> <out.usdc>
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC, OUT = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
act = arm.animation_data.action


def all_fcurves(a):
    # Blender 4.4+/5.x slotted actions: fcurves live under layers/strips/channelbags.
    if len(getattr(a, 'fcurves', [])):
        return list(a.fcurves)
    fcs = []
    for layer in a.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                fcs += list(cb.fcurves)
    return fcs


n = 0
for fc in all_fcurves(act):
    if fc.data_path.endswith('"spine"].location') and fc.array_index in (0, 2):  # X, Z = horizontal
        base = fc.evaluate(bpy.context.scene.frame_start)
        for kp in fc.keyframe_points:
            kp.co.y = base
            kp.handle_left.y = base
            kp.handle_right.y = base
        fc.update()
        n += 1
print("strip_root: flattened", n, "horizontal root fcurves (kept vertical drop)")

bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=OUT, export_animation=True, export_armatures=True,
                      export_materials=False, selected_objects_only=False, root_prim_path="/root")
print("strip_root: exported ->", OUT)
