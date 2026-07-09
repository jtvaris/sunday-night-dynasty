# player_kit.py — Sunday Night Dynasty low-poly player part kit
#
# Headless Blender generator for the coach-mode 3D player upgrade.
# Models every part in SceneKit units (1 Blender meter == 1 scene unit) and at
# the exact sizes the procedural figure in FootballFieldScene.makePlayerNode
# uses today, so the Swift side can swap geometry under the existing joint
# nodes (leg/legR/shin/arm/armR/forearm/helmet/body) without touching any
# animation code.
#
# Usage:
#   Blender --background --python tools/asset-pipeline/player_kit.py -- \
#       --out <export_dir> --preview <png_dir> [--no-export]
#
# Outputs:
#   PlayerKit.usdc   all parts as named root objects (HELMET_SHELL, FACEMASK,
#                    TORSO, THIGH, SHIN, UPPER_ARM, FOREARM, CLEAT, FOOTBALL)
#   preview PNGs     one assembled figure + part lineup, for visual iteration
#
# Material slots (SceneKit re-tints by these names):
#   JERSEY, PANTS, HELMET, SKIN, MASK, BALL, LACES, SHOE

import bpy
import bmesh
import math
import sys
from mathutils import Vector

# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default

OUT_DIR = arg("--out", "/tmp/player_kit")
PREVIEW_DIR = arg("--preview", OUT_DIR)
DO_EXPORT = "--no-export" not in argv

# ----------------------------------------------------------------------------
# Scene reset + materials
# ----------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def material(name, rgba, roughness=0.6, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat

MAT = {
    "JERSEY": material("JERSEY", (0.08, 0.22, 0.45, 1), 0.6),
    "PANTS": material("PANTS", (0.85, 0.83, 0.78, 1), 0.7),
    "HELMET": material("HELMET", (0.05, 0.14, 0.30, 1), 0.25),
    "SKIN": material("SKIN", (0.55, 0.36, 0.24, 1), 0.8),
    "MASK": material("MASK", (0.62, 0.62, 0.64, 1), 0.4, 0.3),
    "BALL": material("BALL", (0.36, 0.18, 0.08, 1), 0.55),
    "LACES": material("LACES", (0.92, 0.92, 0.9, 1), 0.7),
    "SHOE": material("SHOE", (0.1, 0.1, 0.11, 1), 0.5),
}

def new_object(name, mesh_name=None):
    mesh = bpy.data.meshes.new(mesh_name or name)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return obj

def finish(obj, materials, shade_flat=False):
    """Assign material slots and shading.

    Curved surfaces (helmet, torso, limbs, ball) default to SMOOTH shading —
    flat-shaded low-seg cylinders read as boxes from the coach camera. Only
    the hard-edged gear (facemask bars, cleats) passes shade_flat=True.
    """
    for m in materials:
        obj.data.materials.append(MAT[m])
    for poly in obj.data.polygons:
        poly.use_smooth = not shade_flat
    return obj

# ----------------------------------------------------------------------------
# HELMET — dome with jaw flaps, front opening, ear bumps + facemask cage.
# Existing SceneKit helmet: sphere r=0.165 at head. Origin = head center.
# ----------------------------------------------------------------------------
def build_helmet():
    obj = new_object("HELMET_SHELL")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.175)
    # Carve the face opening: delete faces in front-lower area (+Y forward in
    # Blender here; we rotate to SceneKit's +Z forward at export assembly).
    doomed = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y > 0.055 and c.z < 0.06 and abs(c.x) < 0.11:  # face window
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    # Brow ridge: nudge the ring just above the opening forward
    for v in bm.verts:
        if v.co.y > 0.09 and 0.05 < v.co.z < 0.11:
            v.co.y += 0.014
    # Slight back-of-skull stretch + flatten the crown a touch
    for v in bm.verts:
        if v.co.y < 0:
            v.co.y *= 1.08
        if v.co.z > 0.1:
            v.co.z *= 0.94
    # Jaw flaps: extend the two lower side rings downward
    for v in bm.verts:
        if v.co.z < -0.06 and abs(v.co.x) > 0.09:
            v.co.z -= 0.045
            v.co.x *= 0.96
    # Solidify so the shell has a visible rim at the face opening
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.012)
    bm.to_mesh(obj.data)
    bm.free()
    return finish(obj, ["HELMET"])

def build_facemask():
    """Cage: 3 horizontal bars + 2 verticals, one object, MASK material."""
    obj = new_object("FACEMASK")
    bm = bmesh.new()
    def bar(radius, p1, p2, segments=6):
        d = Vector(p2) - Vector(p1)
        m = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments,
                                  radius1=radius, radius2=radius, depth=d.length)
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mid = (Vector(p1) + Vector(p2)) / 2
        for v in m["verts"]:
            v.co = rot @ v.co + mid
    r = 0.008
    # Horizontal bars wrap the face opening (x = sideways, y = forward, z = up)
    for z, w, y in [(0.02, 0.105, 0.155), (-0.02, 0.11, 0.165), (-0.06, 0.10, 0.16)]:
        bar(r, (-w, y * 0.82, z), (0, y, z))
        bar(r, (0, y, z), (w, y * 0.82, z))
        # side connectors back to the shell
        bar(r, (-w, y * 0.82, z), (-w - 0.045, y * 0.45, z + 0.01))
        bar(r, (w, y * 0.82, z), (w + 0.045, y * 0.45, z + 0.01))
    # Two vertical bars
    for x in (-0.035, 0.035):
        bar(r, (x, 0.152, 0.03), (x, 0.163, -0.07))
    bm.to_mesh(obj.data)
    bm.free()
    return finish(obj, ["MASK"], shade_flat=True)   # thin bars stay crisp

# ----------------------------------------------------------------------------
# TORSO — shoulder-pad silhouette. Existing capsule: r=0.26 h=0.85 scaled
# (1.25, 1.0, 0.85). Origin = torso center (SceneKit node "body").
# ----------------------------------------------------------------------------
def smooth_profile(t, keys):
    """Piecewise-smoothstep interpolation through (t, value) keys — the
    slope flattens at every key, so the silhouette has no hard corners."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            s = (t - t0) / (t1 - t0)
            s = s * s * (3 - 2 * s)          # smoothstep
            return v0 + (v1 - v0) * s
    return keys[-1][1]

def build_torso():
    obj = new_object("TORSO")
    bm = bmesh.new()
    # Base: cylinder we sculpt into a V-taper trunk (wide padded shoulders,
    # narrow waist, slight hip flare). Extra rings via subdivision.
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16,
                          radius1=0.26, radius2=0.26, depth=0.78)
    bmesh.ops.subdivide_edges(
        bm,
        edges=[e for e in bm.edges
               if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.1],
        cuts=6)
    # Hips -> waist pinch -> chest -> pad flare, blended smoothly so the
    # silhouette curves instead of kinking at the control rings.
    profile_keys = [(0.0, 1.0), (0.35, 0.86), (0.7, 1.06), (1.0, 1.22)]
    for v in bm.verts:
        t = (v.co.z + 0.39) / 0.78          # 0 hips .. 1 shoulders
        profile = smooth_profile(t, profile_keys)
        v.co.x *= profile * 1.18            # wider side-to-side
        v.co.y *= profile * 0.78            # slimmer front-to-back
    # Pad shelf: round the very top outward so pads read as a ledge but the
    # crown edge stays soft (was a hard flatten).
    for v in bm.verts:
        if v.co.z > 0.37:
            v.co.x *= 1.05
            v.co.y *= 1.02
            v.co.z = 0.39 + (v.co.z - 0.37) * 0.5
    # Tuck the open hip rim in a touch so the bottom edge reads rounded.
    for v in bm.verts:
        if v.co.z < -0.36:
            v.co.x *= 0.95
            v.co.y *= 0.95
    # Neck roll: small cylinder on top (short — the helmet covers the rest)
    neck = bmesh.ops.create_cone(bm, cap_ends=True, segments=12,
                                 radius1=0.09, radius2=0.10, depth=0.07)
    for v in neck["verts"]:
        v.co.z += 0.41
    bm.to_mesh(obj.data)
    bm.free()
    return finish(obj, ["JERSEY"])

# ----------------------------------------------------------------------------
# LIMBS — tapered segments replacing plain capsules; origins at the PIVOT the
# SceneKit nodes use (top of the segment), so a drop-in swap keeps hinges.
# ----------------------------------------------------------------------------
def tapered_limb(name, top_r, bottom_r, length, material, bulge=0.0, bulge_at=0.5):
    obj = new_object(name)
    bm = bmesh.new()
    # 12 radial segments + a mid ring so the bulge curves along the length —
    # smooth-shaded, the limb reads as a rounded muscle, not a box.
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12,
                          radius1=bottom_r, radius2=top_r, depth=length)
    bmesh.ops.subdivide_edges(
        bm,
        edges=[e for e in bm.edges
               if abs(e.verts[0].co.z - e.verts[1].co.z) > length * 0.5],
        cuts=3)
    for v in bm.verts:
        t = (v.co.z + length / 2) / length   # 0 bottom .. 1 top
        if bulge:
            v.co.x *= 1 + bulge * math.exp(-((t - bulge_at) ** 2) / 0.02)
            v.co.y *= 1 + bulge * math.exp(-((t - bulge_at) ** 2) / 0.02)
        # move origin to the TOP (hinge) end
    for v in bm.verts:
        v.co.z -= length / 2
    bm.to_mesh(obj.data)
    bm.free()
    return finish(obj, [material])

# thigh: knee-pad bump low, hip wide top  (existing: capsule .09/.36)
# shin:  calf bulge high, ankle narrow    (existing: capsule .075/.34)
# upper arm: sleeve cap top               (existing: capsule .075/.30)
# forearm: taper to wrist                 (existing: capsule .065/.28)

def build_cleat():
    obj = new_object("CLEAT")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co.x *= 0.085
        v.co.y *= 0.24
        v.co.z *= 0.07
        if v.co.y > 0:                       # toe: lower + narrower
            v.co.z -= 0.02
            v.co.x *= 0.8
            v.co.y *= 1.15
    bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                    offset=0.012, segments=1, affect="EDGES")
    bm.to_mesh(obj.data)
    bm.free()
    return finish(obj, ["SHOE"], shade_flat=True)   # hard gear reads crisp flat

# ----------------------------------------------------------------------------
# FOOTBALL — prolate spheroid + lace strip + white stripes.
# Replaces the current SCNSphere ball. Origin = ball center. Long axis = Y
# (rotated to Z for SceneKit at export).
# ----------------------------------------------------------------------------
def build_football():
    obj = new_object("FOOTBALL")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.10)
    for v in bm.verts:
        v.co.y *= 1.7                         # prolate
        v.co.x *= 0.94
        v.co.z *= 0.94
        # gently pointier ends
        if abs(v.co.y) > 0.13:
            pinch = (abs(v.co.y) - 0.13) / 0.04
            f = max(0.45, 1 - 0.3 * pinch)
            v.co.x *= f
            v.co.z *= f
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, ["BALL"])

    # Laces: small ridge boxes on top
    laces = new_object("FOOTBALL_LACES")
    bm = bmesh.new()
    for i in range(5):
        cube = bmesh.ops.create_cube(bm, size=1)
        for v in cube["verts"]:
            v.co.x *= 0.035
            v.co.y *= 0.012
            v.co.z *= 0.008
            v.co.y += (i - 2) * 0.025
            v.co.z += 0.094
    # spine lace
    spine = bmesh.ops.create_cube(bm, size=1)
    for v in spine["verts"]:
        v.co.x *= 0.008
        v.co.y *= 0.075
        v.co.z *= 0.006
        v.co.z += 0.097
    bm.to_mesh(laces.data)
    bm.free()
    finish(laces, ["LACES"], shade_flat=True)   # tiny boxes, keep hard edges
    laces.parent = obj
    return obj

# ----------------------------------------------------------------------------
# Build all parts
# ----------------------------------------------------------------------------
helmet = build_helmet()
mask = build_facemask()
torso = build_torso()
thigh = tapered_limb("THIGH", 0.105, 0.075, 0.36, "PANTS", bulge=0.16, bulge_at=0.12)
shin = tapered_limb("SHIN", 0.08, 0.05, 0.34, "PANTS", bulge=0.22, bulge_at=0.78)
upper_arm = tapered_limb("UPPER_ARM", 0.095, 0.062, 0.30, "JERSEY", bulge=0.10, bulge_at=0.85)
forearm = tapered_limb("FOREARM", 0.068, 0.045, 0.28, "SKIN", bulge=0.18, bulge_at=0.75)
cleat = build_cleat()
football = build_football()

PARTS = [helmet, mask, torso, thigh, shin, upper_arm, forearm, cleat, football]

# ----------------------------------------------------------------------------
# Preview renders: (1) part lineup, (2) assembled figure approximation
# ----------------------------------------------------------------------------
import os
os.makedirs(PREVIEW_DIR, exist_ok=True)
os.makedirs(OUT_DIR, exist_ok=True)

def add_light_and_camera(target=(0, 0, 0.5), dist=2.6, height=1.4):
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", type="SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", type="SUN"))
    fill.data.energy = 1.0
    fill.rotation_euler = (math.radians(60), 0, math.radians(200))
    scene.collection.objects.link(fill)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    cam.location = (dist * 0.75, -dist, height)
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 800
    scene.world = bpy.data.worlds.new("W")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.14, 0.18, 1)

def render(path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)

# Lineup: lay parts in a row
lineup_offsets = {
    "HELMET_SHELL": (-1.5, 0, 0.55), "FACEMASK": (-1.5, 0, 0.55),
    "TORSO": (-0.85, 0, 0.55), "THIGH": (-0.25, 0, 0.75), "SHIN": (0.05, 0, 0.75),
    "UPPER_ARM": (0.35, 0, 0.75), "FOREARM": (0.6, 0, 0.75),
    "CLEAT": (0.9, 0, 0.55), "FOOTBALL": (1.4, 0, 0.55),
}
for obj in PARTS:
    if obj.name in lineup_offsets:
        obj.location = Vector(lineup_offsets[obj.name])
        if obj.name in ("HELMET_SHELL", "FACEMASK"):
            obj.rotation_euler = (0, 0, math.radians(-140))  # face the camera

add_light_and_camera(target=(0, 0, 0.55), dist=3.2, height=1.1)
render(os.path.join(PREVIEW_DIR, "kit_lineup.png"))

# Helmet closeup for facemask iteration
scene.camera.location = (-1.5 + 0.5, -0.85, 0.75)
_d = Vector((-1.5, 0, 0.55)) - scene.camera.location
scene.camera.rotation_euler = _d.to_track_quat("-Z", "Y").to_euler()
render(os.path.join(PREVIEW_DIR, "helmet_closeup.png"))

# Assembled figure: duplicate parts into a posed player at origin
def dup(obj, loc, rot=(0, 0, 0), scale=(1, 1, 1), parent=None):
    d = obj.copy()
    d.data = obj.data
    d.location = Vector(loc)
    d.rotation_euler = rot
    d.scale = scale
    d.hide_render = False           # originals are hidden; the figure is not
    scene.collection.objects.link(d)
    for child in obj.children:      # bring parented details (ball laces) along
        c = child.copy()
        c.data = child.data
        c.hide_render = False
        c.parent = d
        scene.collection.objects.link(c)
    return d

# hide lineup originals (children too) during figure render
for obj in PARTS:
    obj.hide_render = True
    for child in obj.children:
        child.hide_render = True

# Assemble: torso top ≈ z 1.41, helmet base clears the pads, arms hang from
# the pad edge with a natural elbow bend, legs reach the turf at z 0.
FIG = []
FIG.append(dup(torso, (0, 0, 0.92)))
FIG.append(dup(helmet, (0, 0.01, 1.52), rot=(0, 0, math.radians(180))))
FIG.append(dup(mask, (0, 0.01, 1.52), rot=(0, 0, math.radians(180))))
for sx in (-1, 1):
    FIG.append(dup(thigh, (sx * 0.15, 0, 0.80), rot=(math.radians(-10 * sx), 0, 0)))
    FIG.append(dup(shin, (sx * 0.15, 0.01, 0.45), rot=(math.radians(6), 0, 0)))
    FIG.append(dup(cleat, (sx * 0.15, 0.04, 0.06)))
    FIG.append(dup(upper_arm, (sx * 0.42, 0, 1.36),
                   rot=(math.radians(12), 0, math.radians(-14 * sx))))
    FIG.append(dup(forearm, (sx * 0.47, -0.05, 1.07), rot=(math.radians(35), 0, 0)))
FIG.append(dup(football, (0.9, -0.3, 0.60), rot=(0, 0, math.radians(30))))

add_light_and_camera(target=(0, 0, 0.85), dist=3.0, height=1.4)
render(os.path.join(PREVIEW_DIR, "figure_front.png"))
scene.camera.location = (-2.4, -2.0, 1.5)
direction = Vector((0, 0, 0.85)) - scene.camera.location
scene.camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
render(os.path.join(PREVIEW_DIR, "figure_three_quarter.png"))

# ----------------------------------------------------------------------------
# Export USD: originals only, at origin, +Y forward → SceneKit -Z forward is
# handled on the Swift side with a single container rotation.
# ----------------------------------------------------------------------------
if DO_EXPORT:
    for d in FIG:
        bpy.data.objects.remove(d, do_unlink=True)
    for obj in PARTS:
        obj.hide_render = False
        obj.location = (0, 0, 0)
        obj.rotation_euler = (0, 0, 0)
        for child in obj.children:
            child.hide_render = False
    bpy.ops.object.select_all(action="DESELECT")
    for obj in PARTS:
        obj.select_set(True)
        for child in obj.children:      # parented details (FOOTBALL_LACES)
            child.select_set(True)
    usd_path = os.path.join(OUT_DIR, "PlayerKit.usdc")
    bpy.ops.wm.usd_export(filepath=usd_path, selected_objects_only=True,
                          export_materials=True, convert_orientation=True,
                          export_global_forward_selection="NEGATIVE_Z",
                          export_global_up_selection="Y")
    print("EXPORTED", usd_path)

tri_report = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in PARTS}
print("TRIANGLES", tri_report)
print("DONE")
