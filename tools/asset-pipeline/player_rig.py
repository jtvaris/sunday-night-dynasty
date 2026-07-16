# player_rig.py — skeletal, skinned coach-mode player + clip authoring
# (Animation Overhaul, Option A / Phase 1 substrate). Headless Blender.
#
# Produces a single skinned humanoid mesh + standard humanoid armature, sized in
# SceneKit units (1 Blender meter == 1 scene unit == 1 yard) to the coach-mode
# figure, exported as USD that SceneKit loads with an SCNSkinner. The SAME
# armature (identical bone names/hierarchy) is reused by every clip so a clip's
# name-based keyPaths retarget onto the character (proven Phase 0:
# reference_scenekit_skeletal_pipeline). NOTE: Blender bone "Foo.L" exports to
# USD/SceneKit as "Foo_L" — the animation keyPaths use the underscore form.
#
# Build convention: Blender Z-up, character stands along +Z, FACES +Y. USD
# export (Y-up) maps Blender +Z(up)->scene +Y, Blender +Y(front)->scene +Z
# (downfield). FEET at z=0 so the Swift loader drops the figure onto the turf.
#
# Material slots (SceneKit re-tints by name): JERSEY, PANTS, SKIN, HELMET, MASK.
#
# Usage:
#   blender --background --python player_rig.py -- --out DIR [--preview DIR]
#       (no --clip) -> PlayerRig.usdc   (skinned character, bind pose)
#   blender --background --python player_rig.py -- --out DIR --clip run
#       -> PlayerClip_run.usdc  (same rig, 'run' animation baked)
#
# Clips: run | idle | juke | tackle

import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
OUT = arg("--out", "/tmp/player_rig")
PREVIEW = arg("--preview", None)
CLIP = arg("--clip", None)
MESH_ONLY = "--mesh" in argv   # export a single joined mesh (OBJ) for Mixamo auto-rig upload

P = {
    "ankle_z": 0.10, "knee_z": 0.50, "hip_z": 0.86,
    "waist_z": 1.02, "chest_z": 1.34, "shoulder_z": 1.52,
    "neck_z": 1.60, "head_c_z": 1.80, "head_r": 0.135,
    "hip_dx": 0.13, "shoulder_dx": 0.20, "pad_dx": 0.33,
    "elbow_z": 1.16, "wrist_z": 0.94,
    "arm_dx_elbow": 0.30, "arm_dx_wrist": 0.32,
    "thigh_r": 0.115, "shin_r": 0.085, "ankle_r": 0.07,
    "uparm_r": 0.075, "foarm_r": 0.058, "wrist_r": 0.05,
}

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene

def make_materials():
    def material(name, rgba, rough=0.6, metal=0.0):
        m = bpy.data.materials.new(name); m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = rgba
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        return m
    return {
        "JERSEY": material("JERSEY", (0.08, 0.22, 0.45, 1)),
        "PANTS":  material("PANTS",  (0.85, 0.83, 0.78, 1), 0.7),
        "SKIN":   material("SKIN",   (0.55, 0.36, 0.24, 1), 0.8),
        "HELMET": material("HELMET", (0.05, 0.14, 0.30, 1), 0.25),
        "MASK":   material("MASK",   (0.62, 0.62, 0.64, 1), 0.4, 0.3),
    }
SLOT_ORDER = ["JERSEY", "PANTS", "SKIN", "HELMET", "MASK"]
SLOT_IDX = {n: i for i, n in enumerate(SLOT_ORDER)}

# --- mesh helpers ---
def ring(bm, center, radius, n=10, squash=1.0):
    return [bm.verts.new((center[0] + radius*math.cos(i/n*math.tau),
                          center[1] + radius*squash*math.sin(i/n*math.tau),
                          center[2])) for i in range(n)]
def bridge(bm, r0, r1):
    n = len(r0)
    for i in range(n):
        bm.faces.new((r0[i], r0[(i+1)%n], r1[(i+1)%n], r1[i]))
def cap(bm, r, top=True):
    c = bm.verts.new((sum(v.co.x for v in r)/len(r), sum(v.co.y for v in r)/len(r),
                      sum(v.co.z for v in r)/len(r)))
    n = len(r)
    for i in range(n):
        bm.faces.new((r[i], r[(i+1)%n], c) if top else (r[(i+1)%n], r[i], c))
def tube(bm, pts_radii, squash=1.0, cap_bottom=True, cap_top=True):
    rings = [ring(bm, p, rad, squash=squash) for (p, rad) in pts_radii]
    for a, b in zip(rings[:-1], rings[1:]): bridge(bm, a, b)
    if cap_bottom: cap(bm, rings[0], top=False)
    if cap_top: cap(bm, rings[-1], top=True)

def build_body_mesh(scene, MAT):
    mesh = bpy.data.meshes.new("PlayerMesh")
    obj = bpy.data.objects.new("Player", mesh)
    scene.collection.objects.link(obj)
    bm = bmesh.new()
    slot_layer = bm.faces.layers.int.new("slot")
    for f in bm.faces: f.tag = True
    def seg(pts_radii, slot, squash=1.0, cap_bottom=True, cap_top=True):
        tube(bm, pts_radii, squash=squash, cap_bottom=cap_bottom, cap_top=cap_top)
        for f in bm.faces:
            if not f.tag:
                f[slot_layer] = SLOT_IDX[slot]; f.tag = True
    seg([((0,0,P["hip_z"]-0.02),0.17), ((0,0,P["waist_z"]),0.16),
         ((0,0.01,P["chest_z"]),0.205), ((0,0.015,P["shoulder_z"]),0.24),
         ((0,0.01,P["shoulder_z"]+0.05),0.20)], "JERSEY", squash=0.72)
    seg([((0,0,P["hip_z"]-0.10),0.175), ((0,0,P["hip_z"]+0.02),0.17)],
        "PANTS", squash=0.72, cap_top=False)
    seg([((0,0.01,P["shoulder_z"]+0.02),0.075), ((0,0.01,P["neck_z"]+0.03),0.07)],
        "SKIN", squash=1.0, cap_bottom=False)
    for sx in (-1, 1):
        hx = sx*P["hip_dx"]
        seg([((hx,0,P["hip_z"]),P["thigh_r"]), ((hx,0.005,P["knee_z"]+0.02),P["shin_r"]+0.02),
             ((hx,0,P["knee_z"]-0.02),P["shin_r"]), ((hx,0.01,P["ankle_z"]),P["ankle_r"])],
            "PANTS", squash=0.95)
        seg([((hx,0.02,0.03),0.06), ((hx,0.10,0.02),0.05)], "SKIN", squash=0.7)
    for sx in (-1, 1):
        shx = sx*P["shoulder_dx"]
        seg([((shx,0.01,P["shoulder_z"]+0.02),P["uparm_r"]+0.03),
             ((sx*P["arm_dx_elbow"],0.02,P["elbow_z"]),P["uparm_r"])], "JERSEY")
        seg([((sx*P["arm_dx_elbow"],0.02,P["elbow_z"]-0.02),P["foarm_r"]),
             ((sx*P["arm_dx_wrist"],0.03,P["wrist_z"]),P["wrist_r"])], "SKIN")
        seg([((sx*P["arm_dx_wrist"],0.03,P["wrist_z"]-0.01),P["wrist_r"]+0.005),
             ((sx*P["arm_dx_wrist"],0.05,P["wrist_z"]-0.10),0.035)], "SKIN", squash=0.8)
    hstart = len(bm.verts)
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=P["head_r"])
    for v in bm.verts[hstart:]: v.co += Vector((0,0.01,P["head_c_z"]))
    for f in bm.faces:
        if not f.tag: f[slot_layer] = SLOT_IDX["SKIN"]; f.tag = True
    for name in SLOT_ORDER: obj.data.materials.append(MAT[name])
    bm.to_mesh(mesh)
    mb = bmesh.new(); mb.from_mesh(mesh); sl = mb.faces.layers.int.get("slot")
    for f in mb.faces: f.material_index = f[sl] if sl else 0
    mb.to_mesh(mesh); mb.free(); bm.free()
    if mesh.attributes.get("slot"): mesh.attributes.remove(mesh.attributes["slot"])
    for poly in mesh.polygons: poly.use_smooth = True
    return obj

def build_helmet(scene, MAT):
    hm = bpy.data.meshes.new("HelmetMesh"); ho = bpy.data.objects.new("Helmet", hm)
    scene.collection.objects.link(ho)
    b = bmesh.new()
    bmesh.ops.create_uvsphere(b, u_segments=16, v_segments=10, radius=P["head_r"]*1.28)
    doomed = [f for f in b.faces if f.calc_center_median().y > 0.05
              and f.calc_center_median().z < 0.02 and abs(f.calc_center_median().x) < 0.09]
    bmesh.ops.delete(b, geom=doomed, context="FACES")
    bmesh.ops.solidify(b, geom=list(b.faces), thickness=0.012)
    for v in b.verts: v.co += Vector((0,0.005,P["head_c_z"]+0.02))
    b.to_mesh(hm); b.free()
    hm.materials.append(MAT["HELMET"])
    for poly in hm.polygons: poly.use_smooth = True
    fm = bpy.data.meshes.new("MaskMesh"); fo = bpy.data.objects.new("Facemask", fm)
    scene.collection.objects.link(fo)
    b2 = bmesh.new()
    for zoff in (-0.02, -0.06, -0.10):
        bmesh.ops.create_cone(b2, segments=6, radius1=0.008, radius2=0.008, depth=0.16,
            cap_ends=True, matrix=Matrix.Translation((0, P["head_r"]*1.18+0.02, P["head_c_z"]+zoff))
            @ Matrix.Rotation(math.radians(90), 4, 'Y'))
    b2.to_mesh(fm); b2.free(); fm.materials.append(MAT["MASK"])
    return ho, fo

def build_armature(scene):
    ad = bpy.data.armatures.new("Armature"); ao = bpy.data.objects.new("Armature", ad)
    scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    eb = ad.edit_bones
    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name); b.head = head; b.tail = tail
        if parent: b.parent = parent; b.use_connect = connect
        return b
    hips  = bone("Hips",  (0,0,P["hip_z"]),      (0,0,P["waist_z"]))
    spine = bone("Spine", (0,0,P["waist_z"]),    (0,0,P["chest_z"]), hips, True)
    chest = bone("Chest", (0,0,P["chest_z"]),    (0,0,P["shoulder_z"]), spine, True)
    neck  = bone("Neck",  (0,0,P["shoulder_z"]), (0,0,P["neck_z"]), chest, True)
    bone("Head", (0,0,P["neck_z"]), (0,0,P["head_c_z"]+P["head_r"]), neck, True)
    for s, tag in ((-1,"L"), (1,"R")):
        sh = bone(f"Shoulder.{tag}", (0,0,P["shoulder_z"]), (s*P["shoulder_dx"],0,P["shoulder_z"]), chest, False)
        ua = bone(f"UpperArm.{tag}", (s*P["shoulder_dx"],0.01,P["shoulder_z"]), (s*P["arm_dx_elbow"],0.02,P["elbow_z"]), sh, True)
        fa = bone(f"Forearm.{tag}",  (s*P["arm_dx_elbow"],0.02,P["elbow_z"]), (s*P["arm_dx_wrist"],0.03,P["wrist_z"]), ua, True)
        bone(f"Hand.{tag}", (s*P["arm_dx_wrist"],0.03,P["wrist_z"]), (s*P["arm_dx_wrist"],0.05,P["wrist_z"]-0.12), fa, True)
        th = bone(f"Thigh.{tag}", (s*P["hip_dx"],0,P["hip_z"]), (s*P["hip_dx"],0.005,P["knee_z"]), hips, False)
        sn = bone(f"Shin.{tag}",  (s*P["hip_dx"],0.005,P["knee_z"]), (s*P["hip_dx"],0.01,P["ankle_z"]), th, True)
        bone(f"Foot.{tag}", (s*P["hip_dx"],0.01,P["ankle_z"]), (s*P["hip_dx"],0.12,0.02), sn, True)
    bpy.ops.object.mode_set(mode="OBJECT")
    return ao

def build_rig():
    scene = reset()
    MAT = make_materials()
    body = build_body_mesh(scene, MAT)
    helmet, mask = build_helmet(scene, MAT)
    arm = build_armature(scene)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for o in (helmet, mask):
        vg = o.vertex_groups.new(name="Head")
        vg.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
        m = o.modifiers.new(name="Armature", type="ARMATURE"); m.object = arm
        o.parent = arm
    return scene, arm

# ---------------------------------------------------------------------------
# CLIP AUTHORING — pose the armature's pose bones over frames.
# Bones point head->tail; local Y is along the bone. Limb bones are ~vertical,
# so rotation about LOCAL X swings them fore/aft (sagittal) — the dominant
# running/action axis. Signs verified by rendering.
# ---------------------------------------------------------------------------
def _pose(arm, frame, angles):
    """angles: {bone_name: (rx, ry, rz)} in radians (local bone space)."""
    bpy.context.scene.frame_set(frame)
    for name, (rx, ry, rz) in angles.items():
        pb = arm.pose.bones.get(name)
        if pb is None: continue
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (rx, ry, rz)
        pb.keyframe_insert("rotation_euler", frame=frame)

def _key_root_loc(arm, frame, z):
    """Vertical bob on Hips (root motion in place)."""
    bpy.context.scene.frame_set(frame)
    pb = arm.pose.bones.get("Hips")
    pb.location = (0, z, 0)   # bone-local Y == world Z (up) for the Hips bone
    pb.keyframe_insert("location", frame=frame)

def author_run(arm):
    """A contralateral sprint cycle. 24 frames = one full stride (2 contacts).
    Sign convention (verified by render): +local-X on a downward limb bone swings
    it FORWARD; +local-X on a shin/forearm FLEXES the joint (heel/hand toward body.)
    """
    r = math.radians
    HIP_F, HIP_B = r(42), r(28)      # thigh forward / back
    KNEE_HI, KNEE_LO = r(74), r(14)  # swing-leg flex / stance-leg near-straight
    ARM_F, ARM_B = r(46), r(40)      # shoulder swing forward / back
    ELB = r(84)                      # carried elbow
    LEAN = r(15)                     # forward torso lean
    TWIST = r(10)                    # shoulder/hip counter-rotation
    def torso(lean_mul, twist_sign):
        return {"Spine": (LEAN*0.45*lean_mul, 0, twist_sign*TWIST*0.5),
                "Chest": (LEAN*0.55*lean_mul, 0, -twist_sign*TWIST),
                "Neck":  (-LEAN*0.3, 0, 0)}   # keep head up while torso leans
    def contact(f, right_forward):
        s = 1 if right_forward else -1
        a = {
            # forward leg reaching to plant (near straight); back leg driving off (heel up, knee bent)
            "Thigh.R": (s*HIP_F if right_forward else -HIP_B, 0, 0),
            "Thigh.L": (-HIP_B if right_forward else HIP_F, 0, 0),
            "Shin.R": (KNEE_LO if right_forward else KNEE_HI, 0, 0),
            "Shin.L": (KNEE_HI if right_forward else KNEE_LO, 0, 0),
            "Foot.R": (r(-12) if right_forward else r(20), 0, 0),
            "Foot.L": (r(20) if right_forward else r(-12), 0, 0),
            # arms drive opposite legs
            "UpperArm.R": ((-ARM_B) if right_forward else ARM_F, 0, r(-6)),
            "UpperArm.L": (ARM_F if right_forward else (-ARM_B), 0, r(6)),
            "Forearm.R": (ELB, 0, 0), "Forearm.L": (ELB, 0, 0),
        }
        a.update(torso(1.0, s))
        _pose(arm, f, a)
    def passing(f, right_lifting):
        s = 1 if right_lifting else -1
        a = {
            # lifting leg drives knee up; opposite leg PLANTED (near straight, foot down)
            "Thigh.R": (r(26) if right_lifting else -r(6), 0, 0),
            "Thigh.L": (-r(6) if right_lifting else r(26), 0, 0),
            "Shin.R": (r(58) if right_lifting else r(10), 0, 0),
            "Shin.L": (r(10) if right_lifting else r(58), 0, 0),
            "Foot.R": (r(6) if right_lifting else r(-6), 0, 0),
            "Foot.L": (r(-6) if right_lifting else r(6), 0, 0),
            "UpperArm.R": (r(6) if right_lifting else -r(6), 0, r(-6)),
            "UpperArm.L": (-r(6) if right_lifting else r(6), 0, r(6)),
            "Forearm.R": (ELB*0.85, 0, 0), "Forearm.L": (ELB*0.85, 0, 0),
        }
        a.update(torso(1.0, 0))
        _pose(arm, f, a)
    contact(1, True);    _key_root_loc(arm, 1, -0.02)
    passing(7, False);   _key_root_loc(arm, 7, 0.03)
    contact(13, False);  _key_root_loc(arm, 13, -0.02)
    passing(19, True);   _key_root_loc(arm, 19, 0.03)
    contact(25, True);   _key_root_loc(arm, 25, -0.02)
    return 1, 24

def author_idle(arm):
    r = math.radians
    base = {"UpperArm.R": (0,0,r(-6)), "UpperArm.L": (0,0,r(6)),
            "Forearm.R": (r(-18),0,0), "Forearm.L": (r(-18),0,0),
            "Shin.R": (r(6),0,0), "Shin.L": (r(6),0,0)}
    _pose(arm, 1, base); _key_root_loc(arm, 1, 0.0)
    b2 = dict(base); b2["Chest"] = (r(2),0,0)
    _pose(arm, 30, b2); _key_root_loc(arm, 30, 0.012)
    _pose(arm, 60, base); _key_root_loc(arm, 60, 0.0)
    return 1, 60

def author_juke(arm):
    r = math.radians
    _pose(arm, 1, {"Thigh.R": (r(10),0,0), "Shin.R": (r(30),0,0),
                   "UpperArm.R": (0,0,r(-10)), "UpperArm.L": (0,0,r(10))})
    _key_root_loc(arm, 1, 0.0)
    # plant hard on right, hips shift, torso leans left
    _pose(arm, 7, {"Thigh.R": (r(-14),0,r(-8)), "Shin.R": (r(58),0,0),
                   "Thigh.L": (r(20),0,0), "Shin.L": (r(40),0,0),
                   "Chest": (r(4),0,r(22)), "Spine": (r(2),0,r(14)),
                   "UpperArm.L": (r(-30),0,r(20)), "UpperArm.R": (0,0,r(-14))})
    _key_root_loc(arm, 7, -0.04)
    _pose(arm, 16, {"Thigh.L": (r(-10),0,0), "Shin.L": (r(30),0,0),
                    "Chest": (r(3),0,r(-6)), "Spine": (r(1),0,r(-4)),
                    "UpperArm.R": (0,0,r(-10)), "UpperArm.L": (0,0,r(10))})
    _key_root_loc(arm, 16, 0.0)
    return 1, 16

def author_tackle(arm):
    r = math.radians
    _pose(arm, 1, {"Chest": (r(6),0,0), "UpperArm.R": (r(-20),0,0), "UpperArm.L": (r(-20),0,0),
                   "Shin.R": (r(20),0,0), "Shin.L": (r(20),0,0)})
    _key_root_loc(arm, 1, 0.0)
    # lower, drive, arms wrap forward
    _pose(arm, 8, {"Chest": (r(26),0,0), "Spine": (r(14),0,0),
                   "UpperArm.R": (r(-70),0,r(-18)), "UpperArm.L": (r(-70),0,r(18)),
                   "Forearm.R": (r(-50),0,0), "Forearm.L": (r(-50),0,0),
                   "Thigh.R": (r(24),0,0), "Shin.R": (r(50),0,0),
                   "Thigh.L": (r(-10),0,0), "Shin.L": (r(30),0,0)})
    _key_root_loc(arm, 8, -0.10)
    _pose(arm, 16, {"Chest": (r(30),0,0), "Spine": (r(16),0,0),
                    "UpperArm.R": (r(-80),0,r(-24)), "UpperArm.L": (r(-80),0,r(24)),
                    "Forearm.R": (r(-60),0,0), "Forearm.L": (r(-60),0,0)})
    _key_root_loc(arm, 16, -0.12)
    return 1, 16

CLIP_AUTHORS = {"run": author_run, "idle": author_idle, "juke": author_juke, "tackle": author_tackle}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
scene, arm = build_rig()
os.makedirs(OUT, exist_ok=True)

if MESH_ONLY:
    # Join body + helmet + facemask into ONE mesh (rest/bind pose = no deform)
    # and export OBJ for Mixamo's auto-rigger. Mixamo re-rigs + auto-skins this
    # mesh; the resulting rigged character + mocab clips replace PlayerRig.usdc.
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = "SundayNightPlayer"
    obj_path = os.path.join(OUT, "SundayNightPlayer.obj")
    bpy.ops.object.select_all(action="DESELECT")
    joined.select_set(True)
    bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=True,
                          export_materials=True, forward_axis='NEGATIVE_Z', up_axis='Y')
    print("RIG: Mixamo mesh exported", obj_path)
elif CLIP:
    author = CLIP_AUTHORS[CLIP]
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    f0, f1 = author(arm)
    bpy.ops.object.mode_set(mode="OBJECT")
    scene.frame_start = f0; scene.frame_end = f1
    if arm.animation_data and arm.animation_data.action:
        arm.animation_data.action.name = CLIP.capitalize()
    bpy.ops.object.select_all(action="SELECT")
    out_path = os.path.join(OUT, f"PlayerClip_{CLIP}.usdc")
    bpy.ops.wm.usd_export(filepath=out_path, export_animation=True, export_armatures=True,
                          export_materials=True, selected_objects_only=False, root_prim_path="/root")
    print(f"RIG: clip '{CLIP}' exported {out_path} (frames {f0}-{f1})")
else:
    bpy.ops.object.select_all(action="SELECT")
    out_path = os.path.join(OUT, "PlayerRig.usdc")
    bpy.ops.wm.usd_export(filepath=out_path, export_animation=False, export_armatures=True,
                          export_materials=True, selected_objects_only=False, root_prim_path="/root")
    print("RIG: character exported", out_path)

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    cam_data = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam); cam.location = (3.0, -3.2, 1.2)
    d = Vector((0,0,1.1)) - Vector(cam.location)
    cam.rotation_euler = d.to_track_quat('-Z','Y').to_euler()
    scene.camera = cam
    ld = bpy.data.lights.new("Sun", 'SUN'); light = bpy.data.objects.new("Sun", ld)
    scene.collection.objects.link(light); light.rotation_euler = (math.radians(50),0,math.radians(30))
    scene.render.resolution_x = 400; scene.render.resolution_y = 500
    tag = CLIP or "rig"
    scene.render.filepath = os.path.join(PREVIEW, f"preview_{tag}.png")
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    print("RIG: preview ->", scene.render.filepath)
print("RIG: done")
