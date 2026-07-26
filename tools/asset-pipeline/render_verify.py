# render_verify.py — standardized headless clip-render VERIFICATION harness.
#
# Renders a labeled contact sheet (side profile + 3/4 game-like view at
# start/25%/50%/75%/end) AND runs numeric ground/fall checks on one or more
# PlayerClip_*.usdc clips (58-bone Metarig armature + AmericanFootballMan_001
# mesh), so a clip can be eyeballed and machine-verified before it ships to
# Resources/. Generalizes the throwaway per-session renderers (render_clip.py,
# row_test.py) and the tackle-session lowest-bone-Z monotonicity proof into one
# committed, argument-driven tool.
#
# WHY the checks exist: a seated fall clip (strip_root.py --seat) must drive the
# body DOWN so the lift-only runtime ground clamp can seat it flush. The classic
# bug (a whole July session) is a "fall" whose root travels UP instead — the pile
# flies into the sky with no way for the runtime to pull it down. The --fall
# monotonic-descent check catches exactly that class.
#
# USAGE (argparse after the `--` Blender separator):
#   blender -b -P render_verify.py -- CLIP.usdc [CLIP2.usdc ...] [options]
#   blender -b -P render_verify.py -- --blend FILE.blend --arm "Metarig..." [--action NAME] [options]
#
#   positional CLIP        one or more PlayerClip_*.usdc paths
#   --blend FILE           alternative input: a .blend (with --arm / --action)
#   --arm NAME             armature object name inside the .blend (default: first ARMATURE)
#   --action NAME          action to activate on that armature (default: its current action)
#   --out DIR              output directory (default: /tmp/render_verify_demo)
#   --fall                 treat ALL clips in this run as falls → run the monotonic
#                          root-descent check (net descent + no upward launch)
#   --root-bone NAME       bone tracked for the fall descent check (default: spine)
#   --frames a,b,c,...     sample fractions of the clip (default: 0,0.25,0.5,0.75,1.0)
#   --res N                render resolution, square-ish per view (default: 720)
#   --engine WORKBENCH|EEVEE   render engine (default: WORKBENCH — fast, dep-free)
#   --no-sheet             skip the montage; keep only the individual labeled frames
#   --float-tol F          FAIL if the clip's lowest bone head never comes within F of
#                          turf (it floats). default 0.10
#   --sink-tol F           FAIL if the lowest bone head sinks deeper than F under turf
#                          (badly buried). default 0.50
#   --min-descent F        [--fall] required net root drop start→end (default 0.20)
#   --max-rise F           [--fall] max the root may rise above its start height before
#                          it counts as "launching into the sky" (default 0.15)
#
# OUTPUT: per clip, <out>/<clip>_contactsheet.png plus <out>/frames/<clip>_<view>_f<n>.png,
# a human-readable report, and a machine-readable block delimited by
# ###RENDER_VERIFY_BEGIN### / ###RENDER_VERIFY_END### containing one JSON object per
# clip. EXIT CODE is non-zero if ANY check on ANY clip fails (CI / gate friendly).
#
# ── USD import quirks handled (and why) ─────────────────────────────────────────
#  * The clips reference a sibling `textures/` dir that isn't beside them, so the USD
#    importer logs benign "Couldn't open image file './textures/...png'" warnings.
#    Harmless: this tool overrides materials for the render, so textures are unused.
#  * The imported scene is 4 datablocks: EMPTY `_materials`, MESH
#    `AmericanFootballMan_001` parented to EMPTY `Metarig_Man_013`, and the ARMATURE
#    `Metarig_Man_013.001`. Find the armature BY TYPE, never by name (the numbered
#    suffix varies per clip).
#  * Blender `Foo.L` bones import as `Foo_L`; the Metarig root bone is `spine`. Height
#    is world +Z (feet ≈ z=0); the figure faces −Y so "behind" is the +Y side. Bone
#    HEADS are measured (SceneKit joint nodes sit at bone heads, matching the runtime
#    ground clamp) — same convention as strip_root.py.
#  * The scene frame range is taken from the imported action automatically; short held
#    clips (stance = 2 frames) collapse the sample set — sampled frames are de-duped.
#  * Blender 4.4+/5.x slotted actions keep fcurves under layers/strips/channelbags, but
#    this tool samples poses by frame (no fcurve walking needed), so it is agnostic to
#    the action storage layout.
import bpy, sys, os, json, argparse
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
p = argparse.ArgumentParser(prog="render_verify.py", add_help=True)
p.add_argument("clips", nargs="*", help="PlayerClip_*.usdc path(s)")
p.add_argument("--blend", default=None)
p.add_argument("--arm", default=None)
p.add_argument("--action", default=None)
p.add_argument("--out", default="/tmp/render_verify_demo")
p.add_argument("--fall", action="store_true")
p.add_argument("--root-bone", dest="root_bone", default="spine")
p.add_argument("--frames", default="0,0.25,0.5,0.75,1.0")
p.add_argument("--res", type=int, default=720)
p.add_argument("--engine", default="WORKBENCH")
p.add_argument("--no-sheet", dest="no_sheet", action="store_true")
p.add_argument("--float-tol", dest="float_tol", type=float, default=0.10)
p.add_argument("--sink-tol", dest="sink_tol", type=float, default=0.50)
p.add_argument("--min-descent", dest="min_descent", type=float, default=0.20)
p.add_argument("--max-rise", dest="max_rise", type=float, default=0.15)
p.add_argument("--end-flat-tol", dest="end_flat_tol", type=float, default=None,
               help="[--fall] FAIL if, at the FINAL (held) frame, the highest lower-limb "
                    "head (foot/toe/shin/heel) rises more than F above turf. Catches a "
                    "'chest/head down but a leg kicked into the air' superman/pike freeze "
                    "that fall_descent (spine-head only) certifies as a good fall. The held "
                    "hold pose the runtime freezes on must be flush; measure the leg, not "
                    "just the torso. Report-only (no gate) when unset.")
args = p.parse_args(argv)

ENGINE = {"WORKBENCH": "BLENDER_WORKBENCH", "EEVEE": "BLENDER_EEVEE_NEXT"}.get(
    args.engine.upper(), "BLENDER_WORKBENCH")
FRACS = [float(x) for x in args.frames.split(",") if x.strip() != ""]
os.makedirs(args.out, exist_ok=True)
FRAMEDIR = os.path.join(args.out, "frames")
os.makedirs(FRAMEDIR, exist_ok=True)

import numpy as np


def load_usd(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=path)
    return next(o for o in bpy.data.objects if o.type == "ARMATURE")


def load_blend(path, arm_name, action_name):
    bpy.ops.wm.open_mainfile(filepath=path)
    if arm_name:
        arm = bpy.data.objects[arm_name]
    else:
        arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if action_name:
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = bpy.data.actions[action_name]
    return arm


def setup_render(sc):
    sc.render.engine = ENGINE
    sc.render.resolution_x = args.res
    sc.render.resolution_y = int(args.res * 0.92)
    sc.render.resolution_percentage = 100
    if ENGINE == "BLENDER_WORKBENCH":
        sc.display.shading.light = "STUDIO"
        sc.display.shading.color_type = "MATERIAL"
        sc.display.shading.show_shadows = True
        sc.display.shading.show_cavity = True
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = False
    sc.world.color = (0.09, 0.11, 0.15)
    # a single sun so shadows read the pose
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    import math
    sun.rotation_euler = (math.radians(52), math.radians(10), math.radians(38))
    sun.data.energy = 3.2
    sc.collection.objects.link(sun)
    # only the note stamp — suppress Blender's default date/time/frame/scene clutter
    r = sc.render
    r.use_stamp = True
    r.use_stamp_note = True
    for f in ("use_stamp_time", "use_stamp_date", "use_stamp_render_time",
              "use_stamp_frame", "use_stamp_frame_range", "use_stamp_memory",
              "use_stamp_camera", "use_stamp_lens", "use_stamp_scene",
              "use_stamp_marker", "use_stamp_filename", "use_stamp_hostname",
              "use_stamp_sequencer_strip"):
        if hasattr(r, f):
            setattr(r, f, False)
    r.use_stamp_labels = False
    r.stamp_font_size = max(14, args.res // 30)
    r.stamp_foreground = (1, 1, 1, 1)
    r.stamp_background = (0, 0, 0, 0.65)


def paint(arm, ground_z):
    """Green turf plane at the measured foot plane + bright figure material."""
    import math
    turf = bpy.data.materials.new("turf")
    turf.diffuse_color = (0.14, 0.40, 0.16, 1)
    bpy.ops.mesh.primitive_plane_add(size=16, location=(0, 0, ground_z))
    gp = bpy.context.active_object
    gp.data.materials.append(turf)
    fig = bpy.data.materials.new("figbright")
    fig.diffuse_color = (0.86, 0.47, 0.13, 1)
    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob is not gp:
            ob.data.materials.clear()
            ob.data.materials.append(fig)
    return gp


def lowest_head_z(arm):
    return min((arm.matrix_world @ b.head).z for b in arm.pose.bones)


def bone_z(arm, name):
    b = arm.pose.bones.get(name)
    if b is None:
        b = arm.pose.bones[0]
    return (arm.matrix_world @ b.head).z


def frame_bbox(sc, f, meshes):
    """Single-frame world-space bbox (min, max) over ONLY the given figure meshes —
    never the turf plane, which would balloon the span and zoom the camera out."""
    sc.frame_set(f)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    mins = [1e9] * 3
    maxs = [-1e9] * 3
    for ob in meshes:
        obe = ob.evaluated_get(dg)
        if not obe.data.vertices:
            continue
        for v in obe.data.vertices:
            wv = obe.matrix_world @ v.co
            for i in range(3):
                mins[i] = min(mins[i], wv[i])
                maxs[i] = max(maxs[i], wv[i])
    return mins, maxs


def place_cam(cam, kind, center, ground_z, fig_h, horiz):
    """Re-aim a fixed-zoom camera onto a per-frame figure center. Clips are played
    in-place at runtime (the container supplies world travel) but the raw clip may
    still drift forward, so the camera TRACKS the figure to keep it the same size
    and framed in every cell — a fixed union-fit would shrink it to a dot."""
    cx, cy = center
    if kind == "side":
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = max(horiz, fig_h) * 1.3 + 0.4
        loc = Vector((cx + 8.0, cy, ground_z + fig_h * 0.5))
        aim = Vector((cx, cy, ground_z + fig_h * 0.45))
    else:  # 3/4 game-like: behind (+Y, figure faces -Y) and to the side (+X), elevated
        cam.data.type = "PERSP"
        cam.data.lens = 40
        reach = max(fig_h, horiz) * 1.85 + 0.9
        loc = Vector((cx + reach * 0.60, cy + reach * 0.80, ground_z + fig_h * 1.05))
        aim = Vector((cx, cy, ground_z + fig_h * 0.42))
    cam.location = loc
    cam.rotation_euler = (aim - loc).to_track_quat("-Z", "Y").to_euler()


def render_frame(sc, cam, clip, view, frame, label, out_path):
    sc.camera = cam
    sc.frame_set(frame)
    bpy.context.view_layer.update()
    sc.render.stamp_note_text = "%s | %s | f%d %s" % (clip, view, frame, label)
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)


def read_png(path):
    img = bpy.data.images.load(path)
    w, h, ch = img.size[0], img.size[1], img.channels
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, ch)
    if ch == 3:  # pad to RGBA
        a = np.dstack([a, np.ones((h, w, 1), np.float32)])
    bpy.data.images.remove(img)
    return a  # bottom-up rows, RGBA


def contact_sheet(rows, out_path):
    """rows = list of row-lists of bottom-up RGBA cells; assemble top-down, save."""
    td_rows = []
    for row in rows:
        td_cells = [np.flipud(c) for c in row]  # to top-down
        td_rows.append(np.concatenate(td_cells, axis=1))
    sheet_td = np.concatenate(td_rows, axis=0)
    sheet_bu = np.flipud(sheet_td)  # back to bottom-up for Blender pixels
    H, W = sheet_bu.shape[0], sheet_bu.shape[1]
    out = bpy.data.images.new("sheet", W, H, alpha=True)
    out.pixels = sheet_bu.reshape(-1).tolist()
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)


def verify_clip(source):
    """source = ('usd', path) | ('blend', (path, arm, action))."""
    if source[0] == "usd":
        path = source[1]
        clip = os.path.splitext(os.path.basename(path))[0]
        arm = load_usd(path)
    else:
        path, arm_name, action_name = source[1]
        arm = load_blend(path, arm_name, action_name)
        act = arm.animation_data.action if arm.animation_data else None
        clip = action_name or (act.name if act else os.path.splitext(os.path.basename(path))[0])

    sc = bpy.context.scene
    fs, fe = int(sc.frame_start), int(sc.frame_end)
    span = max(1, fe - fs)
    # figure meshes captured BEFORE the turf plane is added (paint), so framing
    # measures only the player
    fig_meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.data.vertices]

    # ── numeric pass: per-frame lowest bone head + root bone Z over the FULL clip ──
    los = []
    roots = []
    for f in range(fs, fe + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        los.append(lowest_head_z(arm))
        roots.append(bone_z(arm, args.root_bone))
    lo_min, lo_max, lo_final = min(los), max(los), los[-1]
    ground_margin = lo_min  # deepest approach of the lowest joint to turf (z=0)
    ground_z = los[0]       # turf = the standing foot plane at the start frame

    checks = {}
    # ground contact: must reach the turf (not float) and not be badly buried
    floats = ground_margin > args.float_tol
    buried = ground_margin < -args.sink_tol
    checks["ground_contact"] = {
        "margin": round(ground_margin, 4),
        "float_tol": args.float_tol, "sink_tol": args.sink_tol,
        "floats": floats, "buried": buried,
        "pass": (not floats) and (not buried),
    }

    if args.fall:
        r0, rN, rmax = roots[0], roots[-1], max(roots)
        net_descent = r0 - rN
        rise_above_start = rmax - r0
        ok = (net_descent >= args.min_descent) and (rise_above_start <= args.max_rise)
        checks["fall_descent"] = {
            "root_bone": args.root_bone,
            "root_start": round(r0, 4), "root_end": round(rN, 4),
            "net_descent": round(net_descent, 4), "min_descent": args.min_descent,
            "rise_above_start": round(rise_above_start, 4), "max_rise": args.max_rise,
            "pass": ok,
        }

    # ── end-pose flatness ─────────────────────────────────────────────────────────
    # fall_descent tracks ONLY the spine (torso) head, so it certifies the chest coming
    # down while a leg/pelvis can still be kicked into the air — the "superman / pike
    # freeze" that a HELD tackle (runtime hold:true) would lock onto. Measure the FINAL
    # frame's highest lower-limb head so that mode is visible (and gate-able).
    sc.frame_set(fe)
    bpy.context.view_layer.update()
    LIMB_KEYS = ("foot", "toe", "shin", "heel")
    end_limbs = [((arm.matrix_world @ b.head).z - ground_z)
                 for b in arm.pose.bones if any(k in b.name.lower() for k in LIMB_KEYS)]
    end_max_limb = round(max(end_limbs), 4) if end_limbs else None
    end_pelvis = round(roots[-1] - ground_z, 4)  # spine(root) head above turf at hold
    end_pose = {"max_lower_limb_z": end_max_limb, "pelvis_z": end_pelvis,
                "flat_tol": args.end_flat_tol}
    if args.fall and args.end_flat_tol is not None and end_max_limb is not None:
        end_pose["pass"] = end_max_limb <= args.end_flat_tol
        checks["end_pose_flat"] = end_pose

    clip_pass = all(c["pass"] for c in checks.values())

    # ── render pass ──
    setup_render(sc)
    paint(arm, ground_z)
    sample = sorted({fs + round(span * fr) for fr in FRACS})
    labels = {}
    for fr, f in zip(FRACS, [fs + round(span * fr) for fr in FRACS]):
        labels.setdefault(f, "start" if fr == 0 else "end" if fr == 1 else "%d%%" % round(fr * 100))

    # per-frame figure metrics → fixed zoom from the LARGEST single-frame figure so
    # no cell overflows, plus each frame's XY center so the camera tracks the figure
    centers, heights, horizs = {}, [], []
    for f in sample:
        mn, mx = frame_bbox(sc, f, fig_meshes)
        centers[f] = ((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2)
        heights.append(mx[2] - ground_z)
        horizs.append(max(mx[0] - mn[0], mx[1] - mn[1]))
    fig_h = max(heights)
    horiz = max(horizs)

    cam_side = bpy.data.objects.new("side", bpy.data.cameras.new("side"))
    cam_3q = bpy.data.objects.new("3q", bpy.data.cameras.new("3q"))
    sc.collection.objects.link(cam_side)
    sc.collection.objects.link(cam_3q)

    sheet_rows = []
    for view, cam in (("side", cam_side), ("3q", cam_3q)):
        row = []
        for f in sample:
            place_cam(cam, view, centers[f], ground_z, fig_h, horiz)
            outp = os.path.join(FRAMEDIR, "%s_%s_f%03d.png" % (clip, view, f))
            render_frame(sc, cam, clip, view, f, labels.get(f, ""), outp)
            if not args.no_sheet:
                row.append(read_png(outp))
        sheet_rows.append(row)

    sheet_path = os.path.join(args.out, "%s_contactsheet.png" % clip)
    if not args.no_sheet:
        contact_sheet(sheet_rows, sheet_path)
    else:
        sheet_path = None

    summary = {
        "clip": clip, "source": path, "frames": [fs, fe], "sampled": sample,
        "lowest_head_z": {"min": round(lo_min, 4), "max": round(lo_max, 4),
                          "final": round(lo_final, 4)},
        "end_pose": end_pose,
        "checks": checks, "pass": clip_pass,
        "contact_sheet": sheet_path,
    }
    # human-readable
    print("\n── %s ──  frames %d..%d  sampled %s" % (clip, fs, fe, sample))
    print("   lowest_head_z: min=%+.4f max=%+.4f final=%+.4f" % (lo_min, lo_max, lo_final))
    gc = checks["ground_contact"]
    print("   ground_contact: margin=%+.4f  %s%s  [%s]" % (
        gc["margin"], "FLOATS " if gc["floats"] else "", "BURIED" if gc["buried"] else "grounded",
        "PASS" if gc["pass"] else "FAIL"))
    if "fall_descent" in checks:
        fd = checks["fall_descent"]
        print("   fall_descent(%s): start=%+.3f end=%+.3f net=%+.3f (need>=%.2f) rise=%+.3f (need<=%.2f)  [%s]" % (
            fd["root_bone"], fd["root_start"], fd["root_end"], fd["net_descent"],
            fd["min_descent"], fd["rise_above_start"], fd["max_rise"],
            "PASS" if fd["pass"] else "FAIL"))
    _ep = end_pose
    _epg = ("PASS" if _ep.get("pass") else "FAIL") if "pass" in _ep else "report-only"
    print("   end_pose(final f%d): max_lower_limb=%s pelvis=%+.3f (flat_tol=%s)  [%s]" % (
        fe, ("%.3f" % _ep["max_lower_limb_z"]) if _ep["max_lower_limb_z"] is not None else "n/a",
        _ep["pelvis_z"], _ep["flat_tol"], _epg))
    if sheet_path:
        print("   contact sheet -> %s" % sheet_path)
    print("   RESULT: %s" % ("PASS" if clip_pass else "FAIL"))
    return summary


def main():
    sources = []
    if args.blend:
        sources.append(("blend", (args.blend, args.arm, args.action)))
    for c in args.clips:
        sources.append(("usd", c))
    if not sources:
        print("render_verify: no input. Pass CLIP.usdc paths or --blend FILE.", file=sys.stderr)
        sys.exit(2)

    results = [verify_clip(s) for s in sources]

    print("\n###RENDER_VERIFY_BEGIN###")
    for r in results:
        print(json.dumps(r))
    print("###RENDER_VERIFY_END###")

    n_fail = sum(0 if r["pass"] else 1 for r in results)
    print("\nrender_verify: %d clip(s), %d failed, out=%s" % (len(results), n_fail, args.out))
    sys.exit(1 if n_fail else 0)


main()
