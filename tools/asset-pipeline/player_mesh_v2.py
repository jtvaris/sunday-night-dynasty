# player_mesh_v2.py — a CONNECTED, watertight, riggable football-player mesh.
#
# Metaballs proved unreliable (blob or fragment). This builds SOLID overlapping
# primitives (tapered capsules for limbs/torso, spheres for head/helmet/joints,
# a wide slab for shoulder pads) with crisp proportions, unions them with a
# VOXEL REMESH into one watertight surface, and smooths it. Overlap guarantees a
# single connected component that Mixamo's auto-rigger accepts. Later swapped for
# a hero model (Sketchfab / AI) — the mesh is a plug-in art asset.
#
#   blender -b -P player_mesh_v2.py -- --out DIR [--preview DIR]
#
# T-pose (arms out +/-X), FEET at z=0, facing +Y, scene units (~1 = 1 yard).

import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
OUT = arg("--out", "/tmp/player_v2")
PREVIEW = arg("--preview", None)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

bm = bmesh.new()

def capsule(p0, p1, r0, r1, segments=16):
    """A tapered cylinder (cone) from p0 to p1 with rounded end caps (spheres)."""
    a, b = Vector(p0), Vector(p1)
    d = b - a
    length = d.length
    if length < 1e-5:
        return
    # cone axis is +Z; rotate +Z to d
    quat = Vector((0, 0, 1)).rotation_difference(d.normalized())
    mat = Matrix.Translation(a + d * 0.5) @ quat.to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments,
                          radius1=r0, radius2=r1, depth=length, matrix=mat)
    # rounded caps
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments//2,
                              radius=r0, matrix=Matrix.Translation(a))
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments//2,
                              radius=r1, matrix=Matrix.Translation(b))

def sphere(p, r, seg=18):
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg//2, radius=r,
                              matrix=Matrix.Translation(Vector(p)))

def ellipsoid(p, r, sx, sy, sz, seg=18):
    m = Matrix.Translation(Vector(p)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg//2, radius=r, matrix=m)

def box(p, sx, sy, sz):
    m = Matrix.Translation(Vector(p)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_cube(bm, size=2.0, matrix=m)

# heights
ANKLE, KNEE, HIP = 0.10, 0.52, 0.92
WAIST, CHEST, SHO = 1.08, 1.34, 1.52
NECK, HEAD = 1.60, 1.80
HIP_DX, SHO_DX = 0.15, 0.25

# --- Torso: hip -> waist -> chest (tapered capsule, thick = padded), overlapped
capsule((0, 0, HIP-0.04), (0, 0.01, WAIST), 0.20, 0.185)
capsule((0, 0.01, WAIST), (0, 0.03, CHEST), 0.185, 0.235)
capsule((0, 0.03, CHEST), (0, 0.02, SHO), 0.235, 0.22)
# shoulder-pad slab: wide, shallow, rounded — the football silhouette
ellipsoid((0, 0.02, SHO), 0.24, 2.15, 0.72, 0.62)

# --- Neck + head + integrated helmet + facemask
capsule((0, 0.02, SHO-0.02), (0, 0.02, NECK+0.04), 0.13, 0.11)
sphere((0, 0.03, HEAD), 0.175)
ellipsoid((0, 0.01, HEAD+0.03), 0.20, 1.05, 1.05, 1.12)      # helmet shell over head
ellipsoid((0, 0.15, HEAD-0.02), 0.10, 1.2, 0.7, 1.0)         # facemask bump (+Y front)

# --- Arms (T-pose along X): shoulder -> elbow -> wrist -> hand, overlapping
for s in (-1, 1):
    capsule((s*SHO_DX, 0.02, SHO), (s*0.56, 0.02, SHO-0.01), 0.145, 0.115)  # upper arm
    capsule((s*0.56, 0.02, SHO-0.01), (s*0.86, 0.02, SHO-0.02), 0.115, 0.09)  # forearm
    ellipsoid((s*0.95, 0.03, SHO-0.02), 0.085, 1.0, 1.25, 0.7)              # hand

# --- Legs: hip -> knee -> ankle -> foot, overlapping
for s in (-1, 1):
    capsule((s*HIP_DX, 0.0, HIP-0.02), (s*HIP_DX, 0.01, KNEE), 0.15, 0.115)   # thigh
    capsule((s*HIP_DX, 0.01, KNEE), (s*HIP_DX, 0.02, ANKLE), 0.115, 0.085)    # shin
    box((s*HIP_DX, 0.10, 0.045), 0.075, 0.13, 0.05)                          # foot (+Y)

# write bmesh to a mesh object
me = bpy.data.meshes.new("PlayerRaw")
bm.to_mesh(me); bm.free()
body = bpy.data.objects.new("SundayNightPlayer", me)
scene.collection.objects.link(body)
bpy.context.view_layer.objects.active = body
body.select_set(True)

# VOXEL REMESH: union all overlapping primitives into ONE watertight surface
rem = body.modifiers.new("Remesh", type='REMESH')
rem.mode = 'VOXEL'
rem.voxel_size = 0.028
rem.adaptivity = 0.0
bpy.ops.object.modifier_apply(modifier=rem.name)

# light smoothing pass (shrink/smooth) + smooth shading
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.vertices_smooth(factor=0.5, repeat=6)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
for p in body.data.polygons:
    p.use_smooth = True

# decimate a bit if very dense (keep Mixamo upload light)
if len(body.data.polygons) > 8000:
    dec = body.modifiers.new("Dec", type='DECIMATE')
    dec.ratio = 8000 / len(body.data.polygons)
    bpy.ops.object.modifier_apply(modifier=dec.name)

print("V2: verts", len(body.data.vertices), "polys", len(body.data.polygons))

os.makedirs(OUT, exist_ok=True)
obj_path = os.path.join(OUT, "SundayNightPlayer_v2.obj")
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True)
bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=True,
                      export_materials=False, forward_axis='NEGATIVE_Z', up_axis='Y')
print("V2: exported", obj_path)

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    cam_data = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam); cam.location = (3.3, -3.6, 1.4)
    d = Vector((0,0,1.0)) - Vector(cam.location)
    cam.rotation_euler = d.to_track_quat('-Z','Y').to_euler(); scene.camera = cam
    ld = bpy.data.lights.new("Sun", 'SUN'); L = bpy.data.objects.new("Sun", ld)
    scene.collection.objects.link(L); L.rotation_euler = (math.radians(55),0,math.radians(35)); ld.energy = 3
    scene.render.resolution_x = 420; scene.render.resolution_y = 560
    scene.render.filepath = os.path.join(PREVIEW, "player_v2_preview.png")
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    print("V2: preview ->", scene.render.filepath)
print("V2: done")
