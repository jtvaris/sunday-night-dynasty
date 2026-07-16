# mixamo_to_usd.py — convert a Mixamo FBX (auto-rigged character or a mocap
# animation) into a USD that SceneKit loads with an SCNSkinner (+ a skeletal
# clip). Part of the Animation Overhaul mocap pipeline: Mixamo gives us
# motion-captured locomotion; this drops it into the substrate proven in Phase 0
# (reference_scenekit_skeletal_pipeline).
#
# Workflow:
#   1. Upload tools/asset-pipeline/output/SundayNightPlayer.obj to mixamo.com,
#      auto-rig it, then download:
#        - the rigged character (T-pose, "with skin") -> character FBX
#        - each animation (run/idle/sprint/juke/tackle, "with skin", 30fps,
#          "In Place" for locomotion) -> one FBX per clip
#   2. Convert:
#        blender -b -P mixamo_to_usd.py -- --in Character.fbx  --out DIR --name PlayerRig    --character
#        blender -b -P mixamo_to_usd.py -- --in Running.fbx    --out DIR --name PlayerClip_run
#        blender -b -P mixamo_to_usd.py -- --in Idle.fbx       --out DIR --name PlayerClip_idle
#        ... etc.
#   3. Copy the .usdc files into dynasty/dynasty/Resources/.
#
# NOTE: Mixamo names bones "mixamorig:Hips" etc.; we strip the "mixamorig:"
# prefix and the colon so the USD keyPaths are clean and IDENTICAL across the
# character and every clip (name-based retarget requires matching names). All
# clips must come from the SAME rigged character so the skeletons match.

import bpy, sys, os

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
IN = arg("--in")
OUT = arg("--out", "/tmp/mixamo_usd")
NAME = arg("--name", "PlayerClip")
IS_CHARACTER = "--character" in argv

if not IN or not os.path.exists(IN):
    print("mixamo_to_usd: --in FBX not found:", IN); sys.exit(1)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# Import the Mixamo FBX (Y-up; Blender converts to Z-up on import).
bpy.ops.import_scene.fbx(filepath=IN, automatic_bone_orientation=True)

# Strip the "mixamorig:" prefix from bone + vertex-group names so USD keyPaths
# are clean and match across character/clips.
def clean(n): return n.split(":")[-1]
for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    arm.name = "Armature"
    for b in arm.data.bones:
        b.name = clean(b.name)
for me in [o for o in bpy.data.objects if o.type == "MESH"]:
    for vg in me.vertex_groups:
        vg.name = clean(vg.name)

# Normalize scale: Mixamo/FBX imports tiny (cm). Scale the whole rig so the
# character is game-sized (~1.9 scene units tall). Apply the SAME factor to the
# character AND every clip so the shared skeleton matches.
import mathutils
TARGET_H = 1.9
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
zs = []
for o in meshes:
    for corner in o.bound_box:
        zs.append((o.matrix_world @ mathutils.Vector(corner)).z)
height = (max(zs) - min(zs)) if zs else 0.0
if height > 1e-6:
    factor = TARGET_H / height
    for arm in [o for o in bpy.data.objects if o.type == 'ARMATURE']:
        arm.scale = tuple(c * factor for c in arm.scale)
        arm.location = tuple(c * factor for c in arm.location)
    bpy.context.view_layer.update()
    print(f"mixamo_to_usd: scaled x{factor:.1f} (raw height {height:.4f} -> {TARGET_H})")

# Region materials by height so the game can re-tint by slot (the OBJ upload has
# none): head=SKIN, torso+arms=JERSEY, legs=PANTS. Uses each face's world Z.
def region_materials():
    def mk(name, rgba):
        m = bpy.data.materials.new(name); m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = rgba
        return m
    slots = [("JERSEY", (0.08,0.22,0.45,1)), ("PANTS", (0.85,0.83,0.78,1)),
             ("SKIN", (0.55,0.36,0.24,1)), ("HELMET", (0.05,0.14,0.30,1))]
    for o in [x for x in bpy.data.objects if x.type == 'MESH']:
        o.data.materials.clear()
        mats = [mk(n, c) for n, c in slots]
        for m in mats: o.data.materials.append(m)
        idx = {n: i for i, (n, _) in enumerate(slots)}
        mw = o.matrix_world
        for poly in o.data.polygons:
            c = mw @ poly.center
            if   c.z > 1.72: mi = idx["HELMET"]   # helmet dome / head top
            elif c.z > 1.58: mi = idx["SKIN"]      # face/neck
            elif c.z > 0.86: mi = idx["JERSEY"]    # torso + arms
            else:            mi = idx["PANTS"]     # legs
            poly.material_index = mi
region_materials()

# Frame range from the imported action (if any).
has_anim = False
for o in bpy.data.objects:
    if o.animation_data and o.animation_data.action:
        has_anim = True
        act = o.animation_data.action
        scene.frame_start = int(act.frame_range[0])
        scene.frame_end = int(act.frame_range[1])
        act.name = NAME

os.makedirs(OUT, exist_ok=True)
out_path = os.path.join(OUT, f"{NAME}.usdc")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.wm.usd_export(
    filepath=out_path,
    export_animation=(has_anim and not IS_CHARACTER),
    export_armatures=True,
    export_materials=True,
    selected_objects_only=False,
    root_prim_path="/root",
)
kind = "character" if IS_CHARACTER else ("clip" if has_anim else "static")
print(f"mixamo_to_usd: exported {kind} -> {out_path} (frames {scene.frame_start}-{scene.frame_end})")
