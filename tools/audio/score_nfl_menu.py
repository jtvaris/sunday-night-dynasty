#!/usr/bin/env python3
"""Second measurement pass on gen_nfl_menu: does each take match its brief?

analyze_nfl_menu.py answers "is this file usable" (duration, dead air, arc,
loudness). This answers "is it the thing that was ordered" — the traits the
NFL-broadcast brief is actually made of:

  TEMPO        a march ordered at 124 BPM that came back at 78 is a failed
               prompt. Estimated by autocorrelating a percussive onset
               envelope, then reported BOTH as the raw winner and as the
               strength of the autocorrelation AT the requested tempo, so a
               half/double-time reading is visible rather than hidden.
  PERCUSSION   snare/drumline presence = onset density + transient sharpness.
  BAND BALANCE brass body lives around 200-2000 Hz; a take that is all sub-200
               or all 4 kHz+ is a pad wash or a cymbal wash, not a fanfare.
               Measured with ffmpeg bandpasses at full rate (an earlier
               8 kHz-decode version silently reported 0% for the 4 kHz+ band,
               which sits above that decode's Nyquist).

Output is merged into gen_nfl_menu/analysis.json. Nothing is modified.
"""

from __future__ import annotations

import array
import json
import math
import re
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "gen_nfl_menu"
SR = 8000            # onset work only — transients survive this fine
HOP_S = 0.010        # 10 ms envelope


def band_rms_db(path: Path, lo: int, hi: int) -> float:
    """RMS level of one band, measured at the file's own sample rate."""
    af = []
    if lo > 0:
        af.append(f"highpass=f={lo}:poles=2")
    if hi:
        af.append(f"lowpass=f={hi}:poles=2")
    af.append("astats=measure_overall=RMS_level:measure_perchannel=0")
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
         "-map", "0:a:0", "-af", ",".join(af), "-f", "null", "-"],
        capture_output=True, text=True)
    m = re.findall(r"RMS level dB:\s*(-?[\d.]+|-inf)", r.stderr)
    return float(m[-1]) if m and "inf" not in m[-1] else -120.0


def onset_env(path: Path) -> list[float]:
    """Percussive onset strength, adaptively whitened.

    The 300 Hz high-pass is what makes this a DRUM detector rather than a
    note detector — sustained brass and strings move slowly below it, while
    snare/timpani/cymbal attacks all carry energy above it.

    Energy is log-compressed against the TRACK'S OWN mean rather than an
    absolute floor (a first version used `max(s/n, 1.0)`, which made quiet
    frames land on a hard 0 dB shelf, gave the flux a near-zero median, and
    blew every downstream ratio up to 1e12). The positive first difference is
    then whitened against a 0.5 s moving average so a loud section does not
    out-vote a quiet one when peaks are counted.
    """
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
         "-af", "highpass=f=300:poles=2", "-ac", "1", "-ar", str(SR),
         "-f", "s16le", "-acodec", "pcm_s16le", "-"], capture_output=True)
    x = array.array("h")
    x.frombytes(p.stdout[:len(p.stdout) // 2 * 2])
    n = int(SR * HOP_S)
    energy = []
    for i in range(0, len(x) - n, n):
        s = 0.0
        for v in x[i:i + n]:
            s += float(v) * v
        energy.append(s / n)
    if len(energy) < 50:
        return []
    ref = statistics.mean(energy) or 1e-9
    lg = [math.log10(1.0 + 20.0 * e / ref) for e in energy]
    flux = [max(0.0, lg[i] - lg[i - 1]) for i in range(1, len(lg))]
    # adaptive whitening: subtract a centred 0.5 s moving average
    w = int(0.25 / HOP_S)
    out = []
    for i, v in enumerate(flux):
        lo, hi = max(0, i - w), min(len(flux), i + w + 1)
        out.append(max(0.0, v - statistics.mean(flux[lo:hi])))
    return out


def _comb(flux: list[float], lag: int, n_beats: int = 4) -> float:
    """Comb-filter score: energy landing on a grid of `lag`-spaced beats."""
    if lag < 2 or lag * n_beats >= len(flux):
        return 0.0
    tot, cnt = 0.0, 0
    for start in range(0, len(flux) - lag * n_beats, lag):
        tot += sum(flux[start + k * lag] for k in range(n_beats))
        cnt += n_beats
    return tot / max(cnt, 1)


def tempo(flux: list[float], want: float) -> dict:
    """Tempo by comb filter over 50-200 BPM.

    A comb beats plain autocorrelation here because orchestral onsets are
    sparse and uneven; summing energy that lands ON a candidate beat grid is
    less confusable by a single loud bar. The requested tempo's own score is
    reported alongside the winner, so an ambiguous half/double-time reading
    shows up as high `support` rather than as a fake miss.
    """
    if not flux:
        return {}
    lo, hi = int(60 / 200 / HOP_S), int(60 / 50 / HOP_S)
    scores = {lag: _comb(flux, lag) for lag in range(lo, hi)}
    best_lag = max(scores, key=scores.get)
    raw = 60 / (best_lag * HOP_S)
    mean_score = statistics.mean(scores.values()) or 1e-9
    want_best = 0.0
    for mult in (0.5, 1.0, 2.0):
        lag = int(round(60 / (want * mult) / HOP_S))
        if lo <= lag < hi:
            want_best = max(want_best, scores[lag])
    cands = [raw, raw * 2, raw / 2]
    oct_ = min([c for c in cands if 45 <= c <= 220] or [raw], key=lambda c: abs(c - want))
    return {"bpm_raw": round(raw, 1), "bpm_octave_fit": round(oct_, 1),
            "bpm_want": want, "bpm_err": round(abs(oct_ - want), 1),
            "want_tempo_support": round(want_best / max(scores[best_lag], 1e-9), 2),
            "beat_strength": round(scores[best_lag] / mean_score, 2)}


def percussion(flux: list[float], dur: float) -> dict:
    """Onset count with a minimum inter-onset interval, plus peak/median ratio.

    The 80 ms guard is what stops one snare hit being counted as eight; a
    16th note at 200 BPM is 75 ms, so nothing musical is lost.
    """
    if not flux:
        return {}
    pos = [v for v in flux if v > 0] or [1e-9]
    med = statistics.median(pos)
    thr = med + 3 * (statistics.median([abs(v - med) for v in pos]) or 1e-9)
    guard = int(0.08 / HOP_S)
    peaks, last = [], -guard
    for i in range(1, len(flux) - 1):
        if flux[i] >= flux[i - 1] and flux[i] > flux[i + 1] and flux[i] > thr:
            if i - last >= guard:
                peaks.append(i)
                last = i
    p95 = sorted(flux)[int(0.95 * (len(flux) - 1))]
    return {"onsets_per_min": round(len(peaks) / dur * 60, 1),
            "transient_sharpness": round(p95 / med, 2)}


def bands(path: Path) -> dict:
    lo = band_rms_db(path, 0, 200)
    mid = band_rms_db(path, 200, 2000)
    hi = band_rms_db(path, 4000, 0)
    lin = {k: 10 ** (v / 10) for k, v in (("low", lo), ("mid", mid), ("high", hi))}
    tot = sum(lin.values()) or 1e-9
    return {"band_low_pct": round(100 * lin["low"] / tot, 1),
            "band_mid_pct": round(100 * lin["mid"] / tot, 1),
            "band_high_pct": round(100 * lin["high"] / tot, 1),
            "band_mid_minus_high_db": round(mid - hi, 1)}


HDR = (f"{'stem':<24}{'bpm':>6}{'want':>6}{'err':>6}{'sup':>6}{'beat':>6}"
       f"{'ons/m':>7}{'sharp':>7}{'low%':>6}{'mid%':>6}{'hi%':>6}{'m-h':>7}")

# The two menu themes already in the app. Not competitors — a ruler. Every
# metric below is relative, so "is 1200 onsets/min a lot" is only answerable
# against something the user has already accepted for this exact screen.
SHIPPED = ROOT.parents[1] / "dynasty" / "dynasty" / "Resources" / "Audio" / "Music"
BASELINE = ["music_menu_theme_a.m4a", "music_menu_theme_b.m4a"]


def measure(path: Path, want: float, dur: float) -> dict:
    flux = onset_env(path)
    return {**tempo(flux, want), **percussion(flux, dur), **bands(path)}


def show(stem: str, r: dict, want: float) -> None:
    print(f"{stem:<24}{r.get('bpm_octave_fit', 0):>6.1f}{want:>6.0f}"
          f"{r.get('bpm_err', 0):>6.1f}{r.get('want_tempo_support', 0):>6.2f}"
          f"{r.get('beat_strength', 0):>6.2f}{r.get('onsets_per_min', 0):>7.1f}"
          f"{r.get('transient_sharpness', 0):>7.2f}{r.get('band_low_pct', 0):>6.1f}"
          f"{r.get('band_mid_pct', 0):>6.1f}{r.get('band_high_pct', 0):>6.1f}"
          f"{r.get('band_mid_minus_high_db', 0):>7.1f}")


def main() -> None:
    rows = json.loads((OUT / "analysis.json").read_text())
    print(HDR)
    print("-" * len(HDR))
    for r in rows:
        p = ROOT / r["file"]
        m = re.search(r"(\d+)\s*BPM", r["prompt"])
        want = float(m.group(1)) if m else 100.0
        r.update(measure(p, want, r["actual_s"]))
        show(r["stem"], r, want)
    (OUT / "analysis.json").write_text(json.dumps(rows, indent=2))

    print(f"\n--- baseline: menu themes already shipped ---")
    base = []
    for name in BASELINE:
        p = SHIPPED / name
        if not p.exists():
            continue
        dur = float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", str(p)], capture_output=True, text=True).stdout.strip())
        r = measure(p, 80.0, dur)          # r3 menu_grand was ordered 72-84 BPM
        r["stem"], r["file"], r["actual_s"] = p.stem, name, round(dur, 2)
        base.append(r)
        show(p.stem, r, 80.0)
    (OUT / "baseline.json").write_text(json.dumps(base, indent=2))
    print(f"\nmerged into {OUT.name}/analysis.json + baseline.json")


if __name__ == "__main__":
    main()
