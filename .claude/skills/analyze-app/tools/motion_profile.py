#!/usr/bin/env python3
"""Motion profile for simulator screen recordings.

Extracts frames at 10 fps, computes mean absolute frame-diff (PIL), prints a
0-9 intensity timeline plus every freeze (consecutive near-zero diff) longer
than the threshold. This is the validated method used to diagnose and fix the
"stiff and choppy" coach-mode motion (see BACKLOG 2026-07-10): judging
animation from still screenshots is not acceptable evidence.

Usage:
  python3 motion_profile.py <video.mp4> [--fps 10] [--freeze-threshold 0.5]
                            [--crop WxH+X+Y]   # e.g. 320x280+0+60 (3D viewport only)

Acceptance bands (coach mode, validated 2026-07-10):
  - No full freeze >= 0.5 s during or within 2 s after a play
  - Play bursts develop over 3-6+ s (no 0->9->0 spikes under ~2 s)
  - Idle/panel phases keep a living baseline (level >= 1; typically 3-4 w/ weather)
"""
import argparse, os, subprocess, sys, tempfile

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--fps", type=int, default=10)
    ap.add_argument("--freeze-threshold", type=float, default=0.5,
                    help="seconds of near-zero diff reported as a freeze")
    ap.add_argument("--crop", default=None, help="WxH+X+Y crop applied after scale=320:-1")
    args = ap.parse_args()

    try:
        from PIL import Image, ImageChops
    except ImportError:
        sys.exit("Pillow required: python3 -m pip install pillow")

    with tempfile.TemporaryDirectory() as tmp:
        vf = f"fps={args.fps},scale=320:-1"
        if args.crop:
            wh, _, xy = args.crop.partition("+")
            w, h = wh.split("x"); x, y = xy.split("+")
            vf += f",crop={w}:{h}:{x}:{y}"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", args.video,
                        "-vf", vf, os.path.join(tmp, "f%05d.png")], check=True)
        files = sorted(os.listdir(tmp))
        if len(files) < 2:
            sys.exit("too few frames extracted")

        prev, diffs = None, []
        for f in files:
            im = Image.open(os.path.join(tmp, f)).convert("L")
            if prev is not None:
                d = ImageChops.difference(im, prev)
                h = d.histogram()
                diffs.append(sum(i * c for i, c in enumerate(h)) / (im.width * im.height))
            prev = im

    mx = max(diffs) or 1.0
    levels = [min(9, int(v / mx * 9.99)) for v in diffs]
    line = "".join(str(l) for l in levels)
    print(f"frames={len(diffs)} @ {args.fps}fps  max_diff={mx:.2f}  "
          f"mean={sum(diffs)/len(diffs):.2f}")
    for i in range(0, len(line), 50):
        print(f"{i/args.fps:6.1f}s  {line[i:i+50]}")

    # freezes: runs of level 0
    freezes, start = [], None
    for i, l in enumerate(levels + [9]):          # sentinel ends any open run
        if l == 0 and start is None:
            start = i
        elif l != 0 and start is not None:
            dur = (i - start) / args.fps
            if dur >= args.freeze_threshold:
                freezes.append((start / args.fps, dur))
            start = None
    if freezes:
        print(f"\nFREEZES >= {args.freeze_threshold}s ({len(freezes)}):")
        for t, dur in freezes:
            print(f"  at {t:7.1f}s  for {dur:.1f}s")
    else:
        print(f"\nNo freezes >= {args.freeze_threshold}s  ✓")

if __name__ == "__main__":
    main()
