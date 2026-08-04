#!/usr/bin/env python3
"""Master + measure + score the NFL-broadcast dashboard underscore round.

Stage 2 for `generate_nfl_dash.py`. Same mastering as `post_music.py`
(-16 LUFS / -1.5 dBTP, 48 kHz stereo, dead air trimmed off a measured RMS
envelope), reusing that module's functions rather than re-deriving them, so a
take from this round is directly comparable to the shipped dashboard set.

WHAT THE SCORE IS. Nobody in this loop can listen, so the 1-5 is not a
judgement of whether the music is good. It is a measured answer to the one
question that decides whether a take is usable AT ALL on this screen: does it
sit behind reading, or does it pull the eye off the roster? That reduces to
four things ffmpeg can actually measure —

  build_db    loudness of the last third minus the first third. An underscore
              must not go anywhere; anything above ~3 dB is a build.
  arc_db      p95-p10 dynamic spread. A wide arc means quiet passages the ear
              leans into and loud ones it flinches at; both break reading.
  centroid    spectral centroid. The brief is dark-leaning; bright material
              (cymbals, high strings, open brass) is what attention latches to.
  LRA         EBU loudness range. Low = constant. Same idea as arc_db but on
              the perceptual scale the player's ears actually use.

plus hygiene (duration in the 90-150 s brief, no silence tails) and a BLEND
term: distance from the median centroid/LRA of the dashboard tracks already
shipped, because a take that measures beautifully on its own but sits 2 kHz
brighter than everything around it will still stick out in the rotation.

Round 2 of generate_music.py learned that these metrics do NOT predict what the
user likes — the take he picked ranked last on arc. So this score is a FILTER,
not a ranking: it says which takes are disqualified as underscore, and the ear
decides among the rest. Reasons are printed so a low score can be overruled.

Usage:
    python3 post_nfl_dash.py
"""

from __future__ import annotations

import json
import statistics
import subprocess
from pathlib import Path

import audio_common as ac
import post_music as pm

ROOT = Path(__file__).resolve().parent
GEN = ROOT / "gen_nfl_dash"
SHIPPED = ROOT / "shipped_music.json"
MANIFEST = ROOT / "gen_music" / "manifest.json"

ac.TARGET_I, ac.TARGET_TP = -16.0, -1.5

BRIEF_MIN_S, BRIEF_MAX_S = 90.0, 150.0


def reference_band() -> dict:
    """Centroid / LRA / arc of the dashboard tracks already in the game.

    Read off gen_music/manifest.json via shipped_music.json's context map, so
    "blends with the existing set" is measured against what actually ships and
    not against the whole experiment folder.
    """
    if not (SHIPPED.exists() and MANIFEST.exists()):
        return {}
    stems = {s["source_stem"] for s in json.loads(SHIPPED.read_text())
             if s["context"] == "dashboard"}
    ent = [e for e in json.loads(MANIFEST.read_text()) if e["stem"] in stems]
    if not ent:
        return {}
    pick = lambda k: [e[k] for e in ent if e.get(k) is not None]
    med = lambda v: round(statistics.median(v), 2) if v else None
    cent = sorted(pick("centroid_hz"))
    q = lambda v, f: v[min(len(v) - 1, max(0, round(f * (len(v) - 1))))]
    return {"n": len(ent), "centroid_hz": med(cent),
            "LRA": med(pick("LRA")), "arc_db": med(pick("arc_db")),
            # The shipped set is itself broad (a felt-piano bed and a
            # hi-hat loop are both "dashboard"), so blend is judged against
            # its observed 10-90 spread, not against its median. Outside that
            # window is what actually sticks out in the rotation.
            "centroid_p10_p90": [q(cent, 0.10), q(cent, 0.90)] if cent else None,
            "centroid_range": [cent[0], cent[-1]] if cent else None}


def score(m: dict, ref: dict) -> tuple[float, list[str]]:
    """5.0 minus measured reasons it would not work as an underscore."""
    s, why = 5.0, []

    b = abs(m.get("build_db") or 0)
    if b > 6:
        s -= 2; why.append(f"builds {b:.1f} dB across the take")
    elif b > 3:
        s -= 1; why.append(f"drifts {b:.1f} dB")

    a = m.get("arc_db") or 0
    if a > 18:
        s -= 2; why.append(f"{a:.0f} dB dynamic arc")
    elif a > 12:
        s -= 1; why.append(f"{a:.0f} dB arc")

    c = m.get("centroid_hz") or 0
    if c > 3000:
        s -= 2; why.append(f"bright, {c:.0f} Hz centroid")
    elif c > 2200:
        s -= 1; why.append(f"{c:.0f} Hz centroid runs bright")

    lra = m.get("LRA") or 0
    if lra > 10:
        s -= 1.5; why.append(f"LRA {lra:.1f}")
    elif lra > 7:
        s -= 0.5; why.append(f"LRA {lra:.1f} a touch wide")

    if (m.get("peak_pos") or 0) > 0.75 and (m.get("build_db") or 0) > 2:
        s -= 1; why.append("climaxes at the end")

    d = m.get("duration") or 0
    if not (BRIEF_MIN_S <= d <= BRIEF_MAX_S):
        s -= 1; why.append(f"{d:.0f}s outside the 90-150 s brief")

    # The master is trimmed, so a short fade-out costs nothing — it is not in
    # the deliverable. A LONG one is still a signal: the model stopped writing
    # well before the requested length, i.e. it ran out of material.
    tail = m.get("tail_silence_s") or 0
    if tail > 4:
        s -= 0.5; why.append(f"faded out {tail:.1f}s early")

    lo_hi = ref.get("centroid_p10_p90")
    if lo_hi and c:
        lo, hi = lo_hi
        if c < lo * 0.5 or c > hi * 1.5:
            s -= 1; why.append(f"{c:.0f} Hz sits well outside the shipped set "
                               f"({lo:.0f}-{hi:.0f} Hz)")
        elif not (lo <= c <= hi):
            s -= 0.5; why.append(f"{c:.0f} Hz just outside the shipped set "
                                 f"({lo:.0f}-{hi:.0f} Hz)")

    return max(1.0, min(5.0, s)), why


def main() -> None:
    ref = reference_band()
    metas = sorted(GEN.glob("*.json"))
    metas = [m for m in metas if m.name != "metrics.json"]
    if not metas:
        raise SystemExit("no takes — run generate_nfl_dash.py first")

    rows = []
    for mp in metas:
        meta = json.loads(mp.read_text())
        src = mp.parent / meta["file"]
        stem = meta["stem"]

        raw_dur = pm.probe_dur(src)
        t0, t1 = pm.trim_window(src)

        pre = f"atrim=start={t0}:end={t1},asetpts=N/SR/TB"
        chain = ac.master_chain(src, pre_filter=pre)["chain"]
        wav = GEN / f"{stem}.wav"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(src), "-map", "0:a:0", "-vn", "-af", chain,
                    "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", str(wav)])
        if p.returncode != 0:
            raise RuntimeError(f"{stem}: {p.stderr[-600:]}")

        prev = GEN / f"{stem}.m4a"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(wav), "-vn", "-map", "0:a:0",
                    "-c:a", "aac", "-b:a", "192k", str(prev)])
        if p.returncode != 0:
            raise RuntimeError(f"{stem} preview: {p.stderr[-600:]}")

        loud = ac.measure(wav)
        m = {
            "stem": stem, "lane": meta["lane"], "seed": meta["seed"],
            "prompt": meta["prompt"], "round": meta["round"],
            "model": meta["model"], "prediction_id": meta.get("prediction_id"),
            "predict_time": meta.get("predict_time"),
            "requested_duration": meta["requested_duration"],
            "raw_duration": round(raw_dur, 2),
            "lead_silence_s": round(t0, 2),
            "tail_silence_s": round(raw_dur - t1, 2),
            "duration": round(pm.probe_dur(wav), 2),
            "LUFS": loud.get("I"), "dBTP": loud.get("TP"), "LRA": loud.get("LRA"),
        }
        m.update(pm.spectral(wav))
        m.update(pm.structure(wav))
        m["score"], m["reasons"] = score(m, ref)
        m["files"] = {"raw": src.name, "master_wav": wav.name, "preview_m4a": prev.name}
        rows.append(m)
        print(f"  {stem:<26} {m['duration']:6.1f}s  {m['LUFS']!s:>6} LUFS  "
              f"LRA {m['LRA']!s:>4}  cent {m['centroid_hz']!s:>5} Hz  "
              f"arc {m.get('arc_db')!s:>5}  build {m.get('build_db')!s:>5}  "
              f"tail {m['tail_silence_s']:.2f}s  -> {m['score']}")

    rows.sort(key=lambda r: (-r["score"], r["stem"]))

    tsv = GEN / "candidates_nfl_dash.tsv"
    hdr = ["lane", "file", "seed", "duration_s", "LUFS", "LRA", "centroid_hz",
           "arc_db", "build_db", "peak_pos", "tail_silence_s", "score",
           "reason", "prompt"]
    lines = ["\t".join(hdr)]
    for r in rows:
        reason = "; ".join(r["reasons"]) if r["reasons"] else \
            "flat, dark and constant — clean underscore fit"
        lines.append("\t".join(str(x) for x in [
            r["lane"], f"gen_nfl_dash/{r['files']['preview_m4a']}", r["seed"],
            f"{r['duration']:.2f}", r["LUFS"], r["LRA"], r["centroid_hz"],
            r.get("arc_db"), r.get("build_db"), r.get("peak_pos"),
            f"{r['tail_silence_s']:.2f}", r["score"], reason, r["prompt"]]))
    tsv.write_text("\n".join(lines) + "\n")

    gpu = sum(r.get("predict_time") or 0 for r in rows)
    out = {"round": rows[0]["round"], "reference_dashboard_band": ref,
           "gpu_seconds": round(gpu, 1), "rate_usd_per_s": 0.000975,
           "spend_usd": round(gpu * 0.000975, 4), "takes": rows}
    (GEN / "metrics.json").write_text(json.dumps(out, indent=2))
    print(f"\nreference dashboard band: {ref}")
    print(f"GPU {gpu:.1f}s  ->  ${gpu * 0.000975:.4f}")
    print(f"wrote {tsv.name} + metrics.json")


if __name__ == "__main__":
    main()
