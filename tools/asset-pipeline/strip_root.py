# Strip the HORIZONTAL root (spine) translation from a clip so it plays IN PLACE,
# and optionally SEAT its vertical so a fall/tackle lays out ON THE GROUND instead
# of launching into the air.
#
# ── Horizontal (always) ────────────────────────────────────────────────────────
# The tackle/fall/dive segments (pack_segments.json) are sliced from run-into-tackle
# mocap, so the dive/hit carries the actor's forward run momentum — the "spine" root
# fcurve walks ~5.5 units (≈ several yards in-game) which drags the whole mesh off the
# tackle spot. For a fall we want NO horizontal travel: zero the X/Z (array_index 0/2)
# root fcurves to their start value so the body lays out where he was tackled.
#
# ── Vertical seat (--seat) ─────────────────────────────────────────────────────
# The vertical is array_index 1 (the spine bone's local +Y points along world +UP;
# verified: increasing spine.location[1] raises every bone's world Z). A PROPER fall
# clip must drive the body DOWNWARD so its lowest leaf joint dips just under the turf,
# and the runtime ground clamp (SkeletalFigure.updateFootLock, isGrounded branch)
# seats it — that clamp only ever LIFTS, never lowers, so a clip that instead drives
# the root UP leaves the body floating with no way for the runtime to pull it down.
#
# The sliced tackle_a / tackle_b clips do exactly that: their root Y rises
# monotonically to +1.3..1.67 and never lands (measured: at the last frame the LOWEST
# bone sits ~2.6 units above the turf — the whole body has flown into the air). That is
# the "pino nousee ilmaan ja lentää kasassa" bug.
#
# --seat rewrites the vertical fcurve so the lowest bone sits a hair BELOW the turf on
# every keyframe (the runtime clamp then seats it flush). Because a root-Y translation
# rigidly shifts every bone's world Z by gain·Δ (gain measured here, ≈ armature scale),
# the correction is exact and linear: Δroot_Y[f] = (target − lowest_world_Z[f]) / gain.
# target = the rest-feet height at the start frame minus a small margin, so the standing
# start is preserved and the body settles onto the same ground its feet start on. The
# body then descends by its own bone rotations (standing → prone) with its lowest
# contact point glued to the turf — a real fall, no float. NOT for clips with a genuine
# airborne phase (e.g. the pylon dive, which correctly leaps then lands) — seating would
# kill the leap; leave those horizontal-only.
#
# Usage: blender --background --python strip_root.py -- <in.usdc> <out.usdc> [--seat]
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC, OUT = argv[0], argv[1]
SEAT = "--seat" in argv[2:]
SEAT_MARGIN = 0.05   # sink the lowest bone this far under turf so the lift-only clamp always engages

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


fcurves = all_fcurves(act)

# ── 1. Horizontal flatten (X/Z of the spine root) ──────────────────────────────
n = 0
for fc in fcurves:
    if fc.data_path.endswith('"spine"].location') and fc.array_index in (0, 2):
        base = fc.evaluate(bpy.context.scene.frame_start)
        for kp in fc.keyframe_points:
            kp.co.y = base
            kp.handle_left.y = base
            kp.handle_right.y = base
        fc.update()
        n += 1
print("strip_root: flattened", n, "horizontal root fcurves")

# ── 2. Vertical seat (optional) ────────────────────────────────────────────────
if SEAT:
    scene = bpy.context.scene
    fs, fe = scene.frame_start, scene.frame_end
    vfc = next((fc for fc in fcurves
                if fc.data_path.endswith('"spine"].location') and fc.array_index == 1), None)
    if vfc is None:
        print("strip_root: WARNING no vertical spine fcurve — nothing to seat")
    else:
        def lowest_world_z(frame):
            # Measure bone HEADS only — each SceneKit skeleton joint node sits at the
            # bone head (the joint origin), and the runtime ground clamp
            # (SkeletalFigure.updateFootLock) minimises over exactly those node
            # positions. Seating on head+tail would over-sink a downward-pointing leaf
            # (a fingertip) and leave the runtime, which never sees the tail, floating
            # the body by the head/tail gap. Match the runtime: heads only.
            scene.frame_set(int(round(frame)))
            bpy.context.view_layer.update()
            return min((arm.matrix_world @ b.head).z for b in arm.pose.bones)

        # rest-feet height at the standing start frame = the ground we seat onto
        target = lowest_world_z(fs) - SEAT_MARGIN

        # measure gain = d(world Z) / d(root_Y): perturb one keyframe by +1, restore.
        probe = vfc.keyframe_points[len(vfc.keyframe_points) // 2]
        pf = int(round(probe.co.x))
        lo0 = lowest_world_z(pf)
        probe.co.y += 1.0; probe.handle_left.y += 1.0; probe.handle_right.y += 1.0
        vfc.update()
        lo1 = lowest_world_z(pf)
        probe.co.y -= 1.0; probe.handle_left.y -= 1.0; probe.handle_right.y -= 1.0
        vfc.update()
        gain = lo1 - lo0
        print("strip_root: seat gain (worldZ per root_Y) = %.4f  target = %.4f" % (gain, target))
        if abs(gain) < 1e-4:
            print("strip_root: WARNING gain ~0 — vertical axis not world-up? aborting seat")
        else:
            # PASS 1: measure lowest per keyframe frame on the ORIGINAL curve
            frames = sorted({int(round(kp.co.x)) for kp in vfc.keyframe_points})
            lowmap = {f: lowest_world_z(f) for f in frames}
            # PASS 2: shift each keyframe so that frame's lowest bone → target
            for kp in vfc.keyframe_points:
                f = int(round(kp.co.x))
                d = (target - lowmap[f]) / gain
                kp.co.y += d
                kp.handle_left.y += d
                kp.handle_right.y += d
            vfc.update()
            # verify: re-measure across the clip (should all ≈ target)
            checks = [fs, (fs + fe) // 2, fe]
            got = ["f%d:%.3f" % (c, lowest_world_z(c)) for c in checks]
            print("strip_root: seated vertical — lowest now", " ".join(got), "(target %.3f)" % target)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.usd_export(filepath=OUT, export_animation=True, export_armatures=True,
                      export_materials=False, selected_objects_only=False, root_prim_path="/root")
print("strip_root: exported ->", OUT)
