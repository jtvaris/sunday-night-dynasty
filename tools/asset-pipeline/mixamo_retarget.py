# mixamo_retarget.py — retarget a Mixamo animation (mixamorig skeleton) onto the
# Studio Ochi Rigify "Metarig" so the clip transplants onto PlayerRig.usdz by bone
# name (same mechanism as the Ochi football clips). Mixamo's library fills the gaps
# the Ochi pack lacks (backpedal, wrap-tackle, juke, …).
#
#   blender -b -P mixamo_retarget.py -- --in "Mixamo Clip.fbx" \
#       --rig "Studio Ochi American Football Man C_ANIM.fbx" \
#       --out DIR --name PlayerClip_juke [--root]
#
# Method: both FBX import to Z-up in Blender WORLD space (axis conversion sits on
# the object transform). For each mapped bone we take the SOURCE bone's world-space
# rotation delta from its own rest pose and apply that same world delta to the
# TARGET bone's rest pose. Working in world-delta space is roll-agnostic, so the
# differing Mixamo(T-pose) vs Metarig(A-pose) rest orientations don't twist limbs.
# Root (Hips→spine) translation is transferred only with --root (default in-place;
# the game container supplies world movement).

import bpy, sys, os, math, mathutils
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
MIXAMO = arg("--in")
RIG    = arg("--rig")
OUT    = arg("--out", "/tmp/retarget")
NAME   = arg("--name", "PlayerClip_retarget")
WITH_ROOT = "--root" in argv
TARGET_H = 1.9

# mixamorig bone (without prefix) -> Metarig bone
MAP = {
    "Hips": "spine", "Spine": "spine.001", "Spine1": "spine.002", "Spine2": "spine.003",
    "Neck": "spine.005", "Head": "spine.006",
    "LeftShoulder": "shoulder.L", "LeftArm": "upper_arm.L", "LeftForeArm": "forearm.L", "LeftHand": "hand.L",
    "RightShoulder": "shoulder.R", "RightArm": "upper_arm.R", "RightForeArm": "forearm.R", "RightHand": "hand.R",
    "LeftUpLeg": "thigh.L", "LeftLeg": "shin.L", "LeftFoot": "foot.L", "LeftToeBase": "toe.L",
    "RightUpLeg": "thigh.R", "RightLeg": "shin.R", "RightFoot": "foot.R", "RightToeBase": "toe.R",
}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# --- import target rig (Ochi Metarig) ---
bpy.ops.import_scene.fbx(filepath=RIG)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) == 0]:
    bpy.data.objects.remove(o, do_unlink=True)
ochi = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
ochi.animation_data_clear()

# --- import source (Mixamo) ---
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=MIXAMO)
new_objs = set(bpy.data.objects) - before
mix = next(o for o in new_objs if o.type == 'ARMATURE')
# Drop any mesh that rode in with the Mixamo import ("With Skin" downloads include
# the character mesh) so it can't corrupt the height-normalize below — we only
# want the Ochi mesh + the two skeletons.
for o in [o for o in new_objs if o.type == 'MESH']:
    bpy.data.objects.remove(o, do_unlink=True)
act = mix.animation_data.action
fs, fe = int(act.frame_range[0]), int(act.frame_range[1])
print(f"retarget: source frames {fs}..{fe}")

# --- build bone pairs, sorted parent-first by target depth ---
def depth(bone):
    d = 0
    b = bone
    while b.parent: d += 1; b = b.parent
    return d

pairs = []
for src, tgt in MAP.items():
    sb = mix.pose.bones.get("mixamorig:" + src)
    tb = ochi.pose.bones.get(tgt)
    if not sb or not tb:
        print(f"  skip {src}->{tgt} (missing {'src' if not sb else 'tgt'})"); continue
    src_rest_w = (mix.matrix_world @ mix.data.bones["mixamorig:" + src].matrix_local).to_3x3()
    tgt_rest_w = (ochi.matrix_world @ ochi.data.bones[tgt].matrix_local).to_3x3()
    pairs.append((sb, tb, src_rest_w, tgt_rest_w, depth(ochi.data.bones[tgt])))
pairs.sort(key=lambda p: p[4])

for tb in ochi.pose.bones:
    tb.rotation_mode = 'QUATERNION'

ochi_wi = ochi.matrix_world.inverted()
hips_rest_w = (mix.matrix_world @ mix.data.bones["mixamorig:Hips"].matrix_local).to_translation()
spine_rest_w = (ochi.matrix_world @ ochi.data.bones["spine"].matrix_local).to_translation()

scene.frame_start, scene.frame_end = fs, fe
for f in range(fs, fe + 1):
    scene.frame_set(f)
    for sb, tb, src_rest_w, tgt_rest_w, _ in pairs:
        src_cur_w = (mix.matrix_world @ sb.matrix).to_3x3()
        # World rotation delta from rest, applied to the target's rest orientation.
        # Correct for bones whose rest matches across the two rigs (legs, spine,
        # hips) — which covers the clips this pipeline is actually used for
        # (backpedal, juke, jog). It DAMPS arm motion where the rests differ a lot
        # (Mixamo T-pose arms vs Ochi A-pose arms): a source arm swinging up from
        # horizontal becomes the target arm swinging up from down and only reaches
        # chest. Arm-driven clips (throw, catch) come from the Ochi pack instead;
        # a proper T-pose→A-pose arm retarget would need per-bone roll alignment
        # (a real retargeting addon), tracked as future work.
        delta = src_cur_w @ src_rest_w.inverted()
        desired_w3 = delta @ tgt_rest_w
        loc = tb.matrix.to_translation()                    # keep translation (follows parent)
        desired_w4 = Matrix.Translation(ochi.matrix_world @ loc) @ desired_w3.to_4x4()
        tb.matrix = ochi_wi @ desired_w4
        # Keyframe BEFORE the depsgraph update. Updating first re-evaluates the
        # armature from the keyframes inserted so far; a bone not yet keyframed at
        # this frame would snap back to frame 1's value and that stale value would
        # be captured — which silently made every retarget static. Keyframe first
        # so the update sees this frame's key and keeps it (and children still read
        # the updated parent, since the parent was keyframed earlier this pass).
        tb.keyframe_insert('rotation_quaternion', frame=f)
        bpy.context.view_layer.update()                     # children read updated parent
    if WITH_ROOT:
        hips_w = (mix.matrix_world @ mix.pose.bones["mixamorig:Hips"].matrix).to_translation()
        root = ochi.pose.bones["spine"]
        # transfer hip displacement from rest, in the target's space
        disp = (hips_w - hips_rest_w)
        target_w = spine_rest_w + disp
        root.matrix = ochi_wi @ (Matrix.Translation(target_w) @ root.matrix.to_3x3().to_4x4())
        root.keyframe_insert('location', frame=f)           # keyframe before update (see above)
        bpy.context.view_layer.update()

# CRITICAL: drop the Mixamo source armature before export. It still carries its
# original animation on the mixamorig skeleton; if it ships in the USD, the
# loader (and the game) pick up the FIRST animated node — the Mixamo one — whose
# bone names don't match PlayerRig's Metarig, so nothing drives and the clip
# reads as static. Export only the Ochi Metarig (with the baked animation) + mesh.
mix_data = mix.data
bpy.data.objects.remove(mix, do_unlink=True)
if mix_data.users == 0:
    bpy.data.armatures.remove(mix_data)

# --- normalize height to game size, name the action, export USDC ---
zs = []
for o in [x for x in bpy.data.objects if x.type == 'MESH']:
    for c in o.bound_box:
        zs.append((o.matrix_world @ mathutils.Vector(c)).z)
if zs:
    h = max(zs) - min(zs)
    if h > 1e-6:
        f = TARGET_H / h
        ochi.scale = tuple(c * f for c in ochi.scale)
        ochi.location = tuple(c * f for c in ochi.location)
        bpy.context.view_layer.update()
        print(f"retarget: scaled x{f:.2f}")

if ochi.animation_data and ochi.animation_data.action:
    ochi.animation_data.action.name = NAME

os.makedirs(OUT, exist_ok=True)
out_path = os.path.join(OUT, f"{NAME}.usdc")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=out_path, export_animation=True,
                      export_armatures=True, export_materials=False,
                      selected_objects_only=False, root_prim_path="/root")
print("retarget: exported ->", out_path)
