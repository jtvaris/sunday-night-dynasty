# ue_player_to_usd.py — convert the "American Football Player" pack model
# (SK_FOOTBALL_PLAYER.fbx, an Unreal-Engine-style rig) into a game character USDZ
# oriented + scaled to match the existing PlayerRig convention (Z-up, feet at ~0,
# ~1.9u tall, faces +Z after the loader's −90°X standup). Assigns the pack's PBR
# textures to its 3 materials (skin / cloth-uniform / eye).
#   blender -b -P ue_player_to_usd.py -- --fbx SK_FOOTBALL_PLAYER.fbx --tex TEXDIR --out DIR --name PlayerRig
import bpy, sys, os, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(n, d=None): return argv[argv.index(n) + 1] if n in argv else d
FBX = arg("--fbx"); TEX = arg("--tex"); OUT = arg("--out", "/tmp/ue"); NAME = arg("--name", "PlayerRig")
TARGET_H = 1.9

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# --- textures: pick base color + normal per material by filename heuristic ---
def find_tex(*needles):
    for f in sorted(os.listdir(TEX)):
        if f.lower().endswith('.meta'): continue
        low = f.lower()
        if all(n.lower() in low for n in needles) and '_z_' not in low and 'zombie' not in low:
            return os.path.join(TEX, f)
    return None

SKIN_BC  = find_tex("arm", "basecolor", "skin2") or find_tex("arm", "basecolor")
BODY_BC  = find_tex("body", "basecolor")
BODY_N   = find_tex("body", "normal")
EYE_BC   = find_tex("eye", "basecolor")
print("tex skin:", SKIN_BC and os.path.basename(SKIN_BC))
print("tex body:", BODY_BC and os.path.basename(BODY_BC), "normal:", BODY_N and os.path.basename(BODY_N))

TEX_SIZE = int(arg("--texsize", "1024"))
_texcache = {}
def img(path):
    if not path: return None
    if path in _texcache: return _texcache[path]
    try:
        im = bpy.data.images.load(path)
        if max(im.size) > TEX_SIZE:
            im.scale(TEX_SIZE, TEX_SIZE)
        # save the resized copy as PNG on disk and point the image at it, so the
        # USDZ export packs the SMALL version (packing in-memory left the export
        # referencing the original multi-MB .TGA and it failed / bloated).
        tmp = os.path.join(OUT, "tex_tmp"); os.makedirs(tmp, exist_ok=True)
        png = os.path.join(tmp, os.path.splitext(os.path.basename(path))[0] + ".png")
        im.filepath_raw = png; im.file_format = 'PNG'; im.save()
        _texcache[path] = im
        return im
    except Exception as e:
        print("img err", e); return None

def pbr(mat, base, normal=None):
    mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    if base and (bi := img(base)):
        tx = nt.nodes.new('ShaderNodeTexImage'); tx.image = bi
        nt.links.new(tx.outputs['Color'], bsdf.inputs['Base Color'])
    if normal and (ni := img(normal)):
        ni.colorspace_settings.name = 'Non-Color'
        tx = nt.nodes.new('ShaderNodeTexImage'); tx.image = ni
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(tx.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])

for mat in bpy.data.materials:
    low = mat.name.lower()
    if 'blinn' in low:      pbr(mat, SKIN_BC)                 # skin
    elif 'lambert' in low:  pbr(mat, EYE_BC or SKIN_BC)       # eye
    else:                   pbr(mat, BODY_BC, BODY_N)         # cloth / uniform

# --- orient + scale: stand upright (Z-up), feet ~0, TARGET_H tall ---
# Apply the armature's import transform so bones/mesh live in world space, then
# rotate so the tallest axis is +Z (upright) if needed.
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = arm
# bounds
def bounds():
    xs=[];ys=[];zs=[]
    for o in [o for o in bpy.data.objects if o.type=='MESH']:
        for c in o.bound_box:
            w=o.matrix_world @ mathutils.Vector(c); xs.append(w.x);ys.append(w.y);zs.append(w.z)
    return xs,ys,zs
xs,ys,zs = bounds()
ext = {'x':max(xs)-min(xs),'y':max(ys)-min(ys),'z':max(zs)-min(zs)}
tallest = max(ext, key=ext.get)
print("extents", {k:round(v,2) for k,v in ext.items()}, "tallest", tallest)
# UE mannequins import with bones along +Y (tallest Y) — rotate +90° about X so up=+Z
if tallest == 'y':
    arm.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.view_layer.update()
    xs,ys,zs = bounds()

h = max(zs) - min(zs)
if h > 1e-6:
    f = TARGET_H / h
    arm.scale = tuple(c*f for c in arm.scale)
    bpy.context.view_layer.update()
    xs,ys,zs = bounds()
# drop so feet at 0
arm.location.z -= min(zs)
bpy.context.view_layer.update()

os.makedirs(OUT, exist_ok=True)
out_path = os.path.join(OUT, f"{NAME}.usdz")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=out_path, export_animation=False, export_armatures=True,
                      export_materials=True, selected_objects_only=False, root_prim_path="/root")
print("ue: exported ->", out_path)
