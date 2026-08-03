#!/usr/bin/env python3
"""Objective sanity-check on the generated takes.

No ears available, so score each take on measurable proxies for "is this the
sound we asked for":
  centroid   mean spectral centroid (Hz) — a whistle must be bright, a punt
             must be bass-heavy; a category whose takes cluster in the wrong
             band means the prompt missed.
  flatness   spectral flatness 0..1 — near 1 is noise-like (whoosh, crowd),
             near 0 is tonal (whistle).
  crest      peak-to-RMS in dB — high crest is a transient one-shot, low crest
             is a sustained bed. A "one-shot" with crest < ~8 dB is really an
             ambience and probably not usable as an impact.
  attack     ms from clip start to peak — an impact should spike immediately.
"""

from __future__ import annotations

import json
import math
import re
import statistics
from pathlib import Path

import audio_common as ac

ROOT = Path(__file__).resolve().parent

EXPECT = {  # category -> (centroid_lo, centroid_hi, note)
    "kick_punt":         (80, 1800,  "low thump"),
    "kick_place":        (150, 3000, "sharp leather crack"),
    "catch":             (300, 4000, "slap + grip"),
    "throw_whoosh":      (800, 6000, "airy noise"),
    "tackle_impact":     (80, 2500,  "body thud + pad crunch"),
    "whistle":           (1500, 7000, "bright tonal"),
    "shouts":            (200, 3000, "voice"),
    "crowd_boo_extra":   (200, 2500, "crowd"),
    "crowd_gasp_extra":  (200, 2500, "crowd"),
    "crowd_chant_extra": (200, 2500, "crowd"),
}


def spectral(path: Path) -> dict:
    p = ac.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-map", "0:a:0",
                "-af", "aformat=channel_layouts=mono,aspectralstats=measure=centroid+flatness,"
                       "ametadata=print:file=-", "-f", "null", "-"])
    cent, flat = [], []
    for line in p.stdout.splitlines():
        m = re.search(r"lavfi\.aspectralstats\.1\.centroid=([\d.]+)", line)
        if m:
            cent.append(float(m.group(1)))
        m = re.search(r"lavfi\.aspectralstats\.1\.flatness=([\d.]+)", line)
        if m:
            flat.append(float(m.group(1)))
    return {"centroid": statistics.median(cent) if cent else None,
            "flatness": statistics.median(flat) if flat else None}


def dynamics(path: Path) -> dict:
    env, fs = ac.envelope(path, frame_ms=5)
    if not env:
        return {}
    peak = max(env)
    pk_i = env.index(peak)
    live = [v for v in env if v > peak - 60]
    rms = 10 * math.log10(sum(10 ** (v / 10) for v in live) / len(live)) if live else -120
    return {"crest_db": round(peak - rms, 1), "attack_ms": round(pk_i * fs * 1000)}


def main() -> None:
    gen = json.loads((ROOT / "gen" / "manifest.json").read_text())
    rows = []
    for g in gen:
        if g["status"] != "ok":
            continue
        wav = ROOT / g["files"]["ship_wav_16bit"]
        s, d = spectral(wav), dynamics(wav)
        rows.append({**g, **s, **d})

    by_cat: dict[str, list] = {}
    for r in rows:
        by_cat.setdefault(r["category"], []).append(r)

    print(f"{'take':36s} {'dur':>6s} {'LUFS':>7s} {'cent Hz':>8s} {'flat':>5s} {'crest':>6s} {'atk':>5s}  flag")
    suspect: dict[str, list[str]] = {}
    for cat in sorted(by_cat):
        lo, hi, note = EXPECT[cat]
        print(f"\n-- {cat}  (expect centroid {lo}-{hi} Hz: {note})")
        for r in sorted(by_cat[cat], key=lambda x: x["stem"]):
            flags = []
            c = r.get("centroid")
            if c is None or not (lo <= c <= hi):
                flags.append("CENTROID")
            # Crest only means anything for percussive one-shots. A whistle
            # blast and a shouted cadence are SUSTAINED by nature — low crest
            # there is correct, not a defect.
            if cat in ("kick_punt", "kick_place", "catch", "throw_whoosh", "tackle_impact"):
                if (r.get("crest_db") or 0) < 8:
                    flags.append("NO-TRANSIENT")
            if (r.get("out_LUFS") or 0) < -27:
                flags.append("WEAK")
            if flags:
                suspect.setdefault(cat, []).append(r["stem"])
            print(f"{r['stem']:36s} {r['out']['duration']:6.2f} {r['out_LUFS']:7.1f} "
                  f"{(c or 0):8.0f} {(r.get('flatness') or 0):5.3f} "
                  f"{(r.get('crest_db') or 0):6.1f} {(r.get('attack_ms') or 0):5.0f}  "
                  f"{' '.join(flags)}")

    print("\n=== categories with flagged takes ===")
    for cat, st in sorted(suspect.items()):
        print(f"  {cat}: {len(st)}/{len(by_cat[cat])} flagged -> {', '.join(st)}")
    clean = [c for c in by_cat if c not in suspect]
    print("  clean:", ", ".join(sorted(clean)) or "(none)")


if __name__ == "__main__":
    main()
